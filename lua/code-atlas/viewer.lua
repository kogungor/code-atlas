local M = {}

local function starts_with(text, prefix)
  return tostring(text):sub(1, #prefix) == prefix
end

local function normalize_direction(value)
  local dir = tostring(value or "outgoing"):lower()
  if dir ~= "outgoing" and dir ~= "incoming" then
    return "outgoing"
  end
  return dir
end

local function normalize_depth(value)
  local n = tonumber(value) or 2
  n = math.floor(n)
  if n < 0 then
    return 0
  end
  return n
end

local function normalize_node_kind(value)
  local kind = tostring(value or "all"):lower()
  if kind ~= "all" and kind ~= "function" and kind ~= "method" then
    return "all"
  end
  return kind
end

local function count_nodes(map)
  local n = 0
  for _, _ in pairs(map or {}) do
    n = n + 1
  end
  return n
end

local function sorted_neighbors(ids)
  local out = {}
  for _, id in ipairs(ids or {}) do
    out[#out + 1] = id
  end
  table.sort(out)
  return out
end

local function apply_dynamic_only(subgraph)
  local keep = {}
  keep[subgraph.root_id] = true
  for source_id, targets in pairs(subgraph.edge_annotations or {}) do
    for target_id, ann in pairs(targets or {}) do
      if ann.dynamic then
        keep[source_id] = true
        keep[target_id] = true
      end
    end
  end

  local out_nodes = {}
  for id, node in pairs(subgraph.nodes or {}) do
    if keep[id] then
      out_nodes[id] = node
    end
  end
  local out_adj = {}
  for source_id, children in pairs(subgraph.adjacency or {}) do
    if keep[source_id] then
      out_adj[source_id] = {}
      for _, target_id in ipairs(children or {}) do
        local ann = (((subgraph.edge_annotations or {})[source_id] or {})[target_id])
        if keep[target_id] and ann and ann.dynamic then
          out_adj[source_id][#out_adj[source_id] + 1] = target_id
        end
      end
    end
  end

  local out_ann = {}
  for source_id, targets in pairs(subgraph.edge_annotations or {}) do
    if keep[source_id] then
      for target_id, ann in pairs(targets or {}) do
        if keep[target_id] and ann.dynamic then
          out_ann[source_id] = out_ann[source_id] or {}
          out_ann[source_id][target_id] = ann
        end
      end
    end
  end

  return {
    root_id = subgraph.root_id,
    depth_limit = subgraph.depth_limit,
    direction = subgraph.direction,
    nodes = out_nodes,
    adjacency = out_adj,
    edge_annotations = out_ann,
    polymorphic_calls = subgraph.polymorphic_calls,
    backend = subgraph.backend,
    lsp_client_id = subgraph.lsp_client_id,
    include_external = subgraph.include_external,
  }
end

function M.new_session(index, opts)
  opts = opts or {}
  local root_id = opts.root_id
  local session = {
    index = index,
    initial_root_id = root_id,
    focus_root_id = root_id,
    focus_history = { root_id },
    focus_history_index = 1,
    depth_limit = normalize_depth(opts.depth_limit),
    direction = normalize_direction(opts.direction),
    search_query = nil,
    filter_path_prefix = nil,
    dynamic_only = false,
    node_kind_filter = normalize_node_kind(opts.node_kind_filter),
    cache = {
      key = nil,
      subgraph = nil,
      hidden_nodes = 0,
      total_nodes = 0,
    },
    search_matches = {},
    search_match_idx = 0,
  }
  return session
end

function M.push_focus(session, symbol_id)
  if not symbol_id or session.focus_root_id == symbol_id then
    return
  end

  for i = #session.focus_history, session.focus_history_index + 1, -1 do
    table.remove(session.focus_history, i)
  end
  session.focus_history[#session.focus_history + 1] = symbol_id
  session.focus_history_index = #session.focus_history
  session.focus_root_id = symbol_id
end

function M.pan_history(session, step)
  local next_idx = session.focus_history_index + step
  if next_idx < 1 or next_idx > #session.focus_history then
    return false
  end
  session.focus_history_index = next_idx
  session.focus_root_id = session.focus_history[next_idx]
  return true
end

function M.set_search(session, query)
  if not query or query == "" then
    session.search_query = nil
  else
    session.search_query = tostring(query):lower()
  end
end

function M.set_filter_path(session, prefix)
  if not prefix or prefix == "" then
    session.filter_path_prefix = nil
  else
    session.filter_path_prefix = tostring(prefix)
  end
end

function M.toggle_dynamic_only(session)
  session.dynamic_only = not session.dynamic_only
end

function M.set_node_kind_filter(session, value)
  session.node_kind_filter = normalize_node_kind(value)
end

function M.adjust_depth(session, delta)
  session.depth_limit = normalize_depth(session.depth_limit + delta)
end

function M.pan_graph(session, direction)
  local current = session.focus_root_id
  if not current then
    return false
  end

  local next_ids = direction == "out" and (session.index.outgoing[current] or {}) or (session.index.incoming[current] or {})
  local sorted = sorted_neighbors(next_ids)
  if #sorted == 0 then
    return false
  end
  M.push_focus(session, sorted[1])
  return true
end

function M.build_subgraph(session)
  local graph = require("code-atlas.graph")
  local key = table.concat({
    tostring(session.focus_root_id),
    tostring(session.depth_limit),
    tostring(session.direction),
    tostring(session.search_query or ""),
    tostring(session.filter_path_prefix or ""),
    tostring(session.dynamic_only),
    tostring(session.node_kind_filter),
  }, "|")

  if session.cache.key == key and session.cache.subgraph then
    return session.cache.subgraph, {
      hidden_nodes = session.cache.hidden_nodes,
      total_nodes = session.cache.total_nodes,
    }
  end

  local raw = graph.project_subgraph(session.index, session.focus_root_id, {
    depth_limit = session.depth_limit,
    direction = session.direction,
  })
  local total_nodes = count_nodes(raw.nodes)

  local filtered = graph.filter_project_subgraph(raw, function(_, symbol)
    local path_ok = true
    local search_ok = true
    local kind_ok = true

    if session.filter_path_prefix and session.filter_path_prefix ~= "" then
      path_ok = starts_with(tostring(symbol.relpath or symbol.path or ""), session.filter_path_prefix)
    end
    if session.search_query and session.search_query ~= "" then
      local hay = string.format("%s %s", tostring(symbol.name or ""), tostring(symbol.relpath or symbol.path or "")):lower()
      search_ok = hay:find(session.search_query, 1, true) ~= nil
    end

    if session.node_kind_filter ~= "all" then
      local symbol_kind = tostring(symbol.symbol_kind or "Function"):lower()
      if session.node_kind_filter == "method" then
        kind_ok = symbol_kind == "method"
      elseif session.node_kind_filter == "function" then
        kind_ok = symbol_kind == "function"
      end
    end

    return path_ok and search_ok and kind_ok
  end, {
    keep_root = true,
    connected_to_root = true,
  })

  if session.dynamic_only then
    filtered = apply_dynamic_only(filtered)
  end

  local filtered_nodes = count_nodes(filtered.nodes)
  session.cache.key = key
  session.cache.subgraph = filtered
  session.cache.total_nodes = total_nodes
  session.cache.hidden_nodes = math.max(0, total_nodes - filtered_nodes)

  return filtered, {
    hidden_nodes = session.cache.hidden_nodes,
    total_nodes = total_nodes,
  }
end

function M.update_search_matches(session, lines)
  session.search_matches = {}
  session.search_match_idx = 0

  local q = session.search_query
  if not q or q == "" then
    return
  end

  for i, line in ipairs(lines or {}) do
    if tostring(line):lower():find(q, 1, true) then
      session.search_matches[#session.search_matches + 1] = i
    end
  end

  if #session.search_matches > 0 then
    session.search_match_idx = 1
  end
end

function M.jump_to_search_match(session, step)
  local state = require("code-atlas.window").get_state()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return false
  end
  if #session.search_matches == 0 then
    return false
  end

  local next_idx = session.search_match_idx + step
  if next_idx < 1 then
    next_idx = #session.search_matches
  elseif next_idx > #session.search_matches then
    next_idx = 1
  end
  session.search_match_idx = next_idx
  local line = session.search_matches[next_idx]
  vim.api.nvim_win_set_cursor(state.win, { line, 0 })
  return true
end

return M
