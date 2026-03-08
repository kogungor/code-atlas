local M = {}

M.state = {
  last_debug = nil,
}

local function normalize_range(item)
  local primary = item.selectionRange or item.range
  local fallback = item.range or item.selectionRange
  if not primary then
    return { 0, 0, 0, 0 }
  end

  local sr = ((primary.start or {}).line) or 0
  local sc = ((primary.start or {}).character) or 0
  local er = ((fallback["end"] or {}).line) or sr
  local ec = ((fallback["end"] or {}).character) or sc
  return { sr, sc, er, ec }
end

local function normalize_path_from_uri(uri)
  if not uri or uri == "" then
    return nil
  end
  local ok, path = pcall(vim.uri_to_fname, uri)
  if not ok or not path then
    return nil
  end
  return vim.fs.normalize(path)
end

local function is_within_root(path, root)
  if not path or not root then
    return false
  end
  local normalized_root = vim.fs.normalize(root)
  local prefix = normalized_root
  if prefix:sub(-1) ~= "/" then
    prefix = prefix .. "/"
  end
  return path == normalized_root or path:sub(1, #prefix) == prefix
end

local function is_within_any_root(path, roots)
  for _, root in ipairs(roots or {}) do
    if is_within_root(path, root) then
      return true
    end
  end
  return false
end

local function relative_to_cwd(path)
  if not path then
    return nil
  end
  local cwd = vim.fs.normalize(vim.fn.getcwd())
  local prefix = cwd
  if prefix:sub(-1) ~= "/" then
    prefix = prefix .. "/"
  end
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return path
end

local function item_id(item)
  local range = normalize_range(item)
  local uri = item.uri or ""
  local name = item.name or "<anonymous>"
  return string.format("%s:%d:%d:%s", uri, range[1] + 1, range[2] + 1, name)
end

local function node_from_item(item)
  local path = normalize_path_from_uri(item.uri)
  local range = normalize_range(item)
  local name = item.name or "<anonymous>"
  return {
    id = item_id(item),
    name = name,
    symbol_kind = "Function",
    lang = nil,
    path = path,
    relpath = relative_to_cwd(path),
    range = range,
    detail = item.detail,
    source = "lsp",
  }
end

local function attached_clients(bufnr)
  return vim.lsp.get_clients({ bufnr = bufnr }) or {}
end

local function client_workspace_roots(client)
  local roots = {}

  for _, folder in ipairs(client.workspace_folders or {}) do
    local path = normalize_path_from_uri(folder.uri)
    if path then
      roots[#roots + 1] = path
    end
  end

  local config_root = client.config and client.config.root_dir
  if config_root and config_root ~= "" then
    roots[#roots + 1] = vim.fs.normalize(config_root)
  end

  local deduped = {}
  local seen = {}
  for _, root in ipairs(roots) do
    if not seen[root] then
      seen[root] = true
      deduped[#deduped + 1] = root
    end
  end
  return deduped
end

local function workspace_roots(bufnr, fallback_root)
  local roots = {}
  for _, client in ipairs(attached_clients(bufnr)) do
    for _, root in ipairs(client_workspace_roots(client)) do
      roots[#roots + 1] = root
    end
  end

  if #roots == 0 and fallback_root and fallback_root ~= "" then
    roots[#roots + 1] = vim.fs.normalize(fallback_root)
  end

  local deduped = {}
  local seen = {}
  for _, root in ipairs(roots) do
    if not seen[root] then
      seen[root] = true
      deduped[#deduped + 1] = root
    end
  end

  return deduped
end

local function set_last_debug(payload)
  M.state.last_debug = vim.deepcopy(payload)
end

local supports_method

local function client_summary(client, bufnr)
  return {
    id = client.id,
    name = client.name,
    supports_prepare = supports_method(client, "textDocument/prepareCallHierarchy", bufnr),
    supports_incoming = supports_method(client, "callHierarchy/incomingCalls", bufnr),
    supports_outgoing = supports_method(client, "callHierarchy/outgoingCalls", bufnr),
    offset_encoding = client.offset_encoding,
    roots = client_workspace_roots(client),
  }
end

supports_method = function(client, method, bufnr)
  if not client then
    return false
  end
  if type(client.supports_method) ~= "function" then
    return false
  end
  local ok, supported = pcall(client.supports_method, client, method, { bufnr = bufnr })
  return ok and supported == true
end

local function call_hierarchy_clients(bufnr)
  local out = {}
  for _, client in ipairs(attached_clients(bufnr)) do
    if supports_method(client, "textDocument/prepareCallHierarchy", bufnr) then
      out[#out + 1] = client
    end
  end
  return out
end

local function first_offset_encoding(bufnr)
  local clients = attached_clients(bufnr)
  for _, client in ipairs(clients or {}) do
    if client.offset_encoding and client.offset_encoding ~= "" then
      return client.offset_encoding
    end
  end
  return "utf-16"
end

local function make_position_params(bufnr, row, col, encoding)
  local params = vim.lsp.util.make_position_params(0, encoding)
  params.textDocument = params.textDocument or {
    uri = vim.uri_from_bufnr(bufnr),
  }
  params.position = {
    line = math.max(0, tonumber(row) or 0),
    character = math.max(0, tonumber(col) or 0),
  }
  return params
end

local function flatten_results(responses)
  local out = {}
  for _, response in pairs(responses or {}) do
    local result = response and response.result
    if type(result) == "table" then
      if result.uri or result.name then
        out[#out + 1] = result
      else
        for _, item in ipairs(result) do
          out[#out + 1] = item
        end
      end
    end
  end
  return out
end

local function request_sync(bufnr, method, params, timeout_ms)
  local ok, responses = pcall(vim.lsp.buf_request_sync, bufnr, method, params, timeout_ms)
  if not ok then
    return nil, tostring(responses)
  end
  return responses, nil
end

local function extract_items(result)
  if type(result) ~= "table" then
    return {}
  end
  if result.uri or result.name then
    return { result }
  end
  return result
end

local function pick_prepare_item(responses, preferred_client_ids)
  local function try_client_id(client_id)
    local response = (responses or {})[client_id]
    local items = extract_items(response and response.result)
    if #items > 0 then
      return items[1], client_id
    end
    return nil, nil
  end

  for _, client_id in ipairs(preferred_client_ids or {}) do
    local item, matched = try_client_id(client_id)
    if item then
      return item, matched
    end
  end

  for client_id, response in pairs(responses or {}) do
    local items = extract_items(response and response.result)
    if #items > 0 then
      return items[1], client_id
    end
  end

  return nil, nil
end

local function prepare_error_message(responses, preferred_client_ids)
  local ids = preferred_client_ids or {}
  if #ids == 0 then
    for client_id, _ in pairs(responses or {}) do
      ids[#ids + 1] = client_id
    end
  end

  for _, client_id in ipairs(ids) do
    local response = (responses or {})[client_id]
    local err = response and response.error
    if err then
      local msg = err.message or err.code or "unknown error"
      return tostring(msg)
    end
  end

  return nil
end

local function flatten_results_for_client(responses, client_id)
  if not responses then
    return {}
  end
  if client_id then
    local response = responses[client_id]
    return flatten_results({ [client_id] = response })
  end
  return flatten_results(responses)
end

local function prepare_item(bufnr, opts)
  opts = opts or {}
  local preferred_clients = call_hierarchy_clients(bufnr)
  local all_clients = attached_clients(bufnr)
  if #all_clients == 0 then
    return nil, "no lsp client attached"
  end

  local encoding = first_offset_encoding(bufnr)
  local preferred_ids = {}
  for _, client in ipairs(preferred_clients) do
    preferred_ids[#preferred_ids + 1] = client.id
  end
  for _, client in ipairs(all_clients) do
    preferred_ids[#preferred_ids + 1] = client.id
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local positions = opts.positions or {
    { row = cursor[1] - 1, col = cursor[2] },
  }

  local last_err = nil
  local base_timeout = math.max(100, tonumber(opts.timeout_ms) or 1200)
  local retries = {
    base_timeout,
    math.max(base_timeout, math.min(base_timeout * 3, 5000)),
  }

  for _, pos in ipairs(positions) do
    for _, timeout_ms in ipairs(retries) do
      local params = make_position_params(bufnr, pos.row, pos.col, encoding)
      local responses, request_err = request_sync(bufnr, "textDocument/prepareCallHierarchy", params, timeout_ms)
      if responses then
        local item, client_id = pick_prepare_item(responses, preferred_ids)
        if item then
          return {
            item = item,
            client_id = client_id,
          }, nil
        end

        local response_error = prepare_error_message(responses, preferred_ids)
        if response_error then
          last_err = response_error
        end
      else
        last_err = request_err
      end
    end
  end

  if last_err then
    return nil, "prepareCallHierarchy request failed: " .. tostring(last_err)
  end
  return nil, "lsp returned no call hierarchy item"
end

local function fetch_calls(bufnr, item, direction, timeout_ms, client_id)
  local method = direction == "incoming" and "callHierarchy/incomingCalls" or "callHierarchy/outgoingCalls"
  local responses = request_sync(bufnr, method, { item = item }, timeout_ms)
  if not responses then
    return {}
  end
  return flatten_results_for_client(responses, client_id)
end

local function child_item(call_record, direction)
  if type(call_record) ~= "table" then
    return nil
  end
  if direction == "incoming" then
    if type(call_record.from) == "table" and call_record.from.uri then
      return call_record.from
    end
    if call_record.from and call_record.from[1] then
      return call_record.from[1]
    end
    return nil
  end
  if type(call_record.to) == "table" and call_record.to.uri then
    return call_record.to
  end
  if call_record.to and call_record.to[1] then
    return call_record.to[1]
  end
  return nil
end

local function dedupe(list)
  local seen = {}
  local out = {}
  for _, value in ipairs(list or {}) do
    if not seen[value] then
      seen[value] = true
      out[#out + 1] = value
    end
  end
  return out
end

function M.call_hierarchy_subgraph(bufnr, opts)
  opts = opts or {}
  local direction = opts.direction == "incoming" and "incoming" or "outgoing"
  local depth_limit = math.max(0, math.floor(tonumber(opts.depth_limit) or 2))
  local timeout_ms = math.max(100, tonumber(opts.timeout_ms) or 1200)
  local include_external = opts.include_external == true
  local roots = workspace_roots(bufnr, opts.root or vim.fn.getcwd())
  local debug = {
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    bufnr = bufnr,
    direction = direction,
    depth_limit = depth_limit,
    include_external = include_external,
    roots = roots,
    clients = {},
  }
  for _, client in ipairs(attached_clients(bufnr)) do
    debug.clients[#debug.clients + 1] = client_summary(client, bufnr)
  end

  local prepared, err = prepare_item(bufnr, {
    timeout_ms = timeout_ms,
    positions = opts.positions,
  })
  if not prepared then
    debug.error = err
    set_last_debug(debug)
    return nil, err
  end
  local root_item = prepared.item
  local client_id = prepared.client_id
  debug.selected_client_id = client_id
  debug.root_item = root_item and root_item.name or nil

  local root_node = node_from_item(root_item)
  local nodes = {
    [root_node.id] = root_node,
  }
  local adjacency = {
    [root_node.id] = {},
  }
  local queue = {
    { item = root_item, id = root_node.id, depth = 0 },
  }
  local expanded = {}

  while #queue > 0 do
    local current = table.remove(queue, 1)
    adjacency[current.id] = adjacency[current.id] or {}

    if current.depth < depth_limit and not expanded[current.id] then
      expanded[current.id] = true
      local calls = fetch_calls(bufnr, current.item, direction, timeout_ms, client_id)
      for _, call_record in ipairs(calls or {}) do
        local target_item = child_item(call_record, direction)
        if target_item and target_item.uri then
          local target_node = node_from_item(target_item)
          if include_external or is_within_any_root(target_node.path, roots) then
            nodes[target_node.id] = nodes[target_node.id] or target_node
            adjacency[current.id][#adjacency[current.id] + 1] = target_node.id
            queue[#queue + 1] = {
              item = target_item,
              id = target_node.id,
              depth = current.depth + 1,
            }
          end
        end
      end
      adjacency[current.id] = dedupe(adjacency[current.id])
    end
  end

  local edge_count = 0
  for _, children in pairs(adjacency) do
    edge_count = edge_count + #children
  end

  debug.node_count = vim.tbl_count(nodes)
  debug.edge_count = edge_count
  set_last_debug(debug)

  return {
    root_id = root_node.id,
    root_path = root_node.path,
    direction = direction,
    depth_limit = depth_limit,
    include_external = include_external,
    nodes = nodes,
    adjacency = adjacency,
    backend = "lsp_call_hierarchy",
    lsp_client_id = client_id,
  }, nil
end

function M.is_available(bufnr)
  return #attached_clients(bufnr) > 0
end

function M.client_debug_info(bufnr)
  local out = {}
  for _, client in ipairs(attached_clients(bufnr)) do
    out[#out + 1] = client_summary(client, bufnr)
  end
  return out
end

function M.get_last_debug()
  return vim.deepcopy(M.state.last_debug)
end

return M
