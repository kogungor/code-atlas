local M = {}

local NODE_TYPES = {
  ["function"] = true,
  ["type"] = true,
  ["file"] = true,
  ["module"] = true,
  ["package"] = true,
  ["test"] = true,
}

local function to_bool(value, fallback)
  if value == nil then
    return fallback
  end
  if type(value) == "boolean" then
    return value
  end
  local text = tostring(value):lower()
  if text == "1" or text == "true" or text == "yes" or text == "on" then
    return true
  end
  if text == "0" or text == "false" or text == "no" or text == "off" then
    return false
  end
  return fallback
end

local function normalize_build_opts(opts)
  opts = opts or {}
  return {
    include_tests = to_bool(opts.include_tests, true),
    include_imports = to_bool(opts.include_imports, true),
    include_external = to_bool(opts.include_external, false),
    include_types = to_bool(opts.include_types, true),
  }
end

local function normalize_snapshot_opts(opts)
  opts = opts or {}
  local format = tostring(opts.format or "json"):lower()
  if format ~= "json" and format ~= "jsonl" then
    format = "json"
  end
  return {
    format = format,
    pretty = to_bool(opts.pretty, false),
  }
end

local function is_test_symbol(symbol)
  local rel = (symbol.relpath or symbol.path or ""):lower()
  if rel:find("/test", 1, true) or rel:find("spec", 1, true) then
    return true
  end
  if rel:find("_test%.") then
    return true
  end
  local name = (symbol.name or ""):lower()
  if name:sub(1, 4) == "test" then
    return true
  end
  return false
end

local function add_node(nodes, seen, node)
  if not node or not node.id then
    return
  end
  if seen[node.id] then
    return
  end
  seen[node.id] = true
  nodes[#nodes + 1] = node
end

local function add_edge(edges, seen, edge)
  if not edge or not edge.source or not edge.target then
    return
  end
  local key = string.format("%s|%s|%s", edge.type or "related", edge.source, edge.target)
  if seen[key] then
    return
  end
  seen[key] = true
  edges[#edges + 1] = edge
end

local function add_edge_count(edge_type_counts, edge_type)
  edge_type_counts[edge_type] = (edge_type_counts[edge_type] or 0) + 1
end

local function edge_record(edge_type, source, target, attrs)
  local edge = {
    type = edge_type,
    source = source,
    target = target,
  }
  for key, value in pairs(attrs or {}) do
    edge[key] = value
  end
  return edge
end

local function type_node_id(symbol)
  local container = symbol.container
  if not container or container == "" then
    return nil
  end
  local rel = symbol.relpath or symbol.path or ""
  return string.format("type:%s:%s", rel, container)
end

local function resolution_edge_lookup(index)
  local lookup = {}
  for source_id, entries in pairs(index.call_resolutions or {}) do
    lookup[source_id] = lookup[source_id] or {}
    for _, item in ipairs(entries or {}) do
      for _, target in ipairs(item.targets or {}) do
        if target.id then
          lookup[source_id][target.id] = {
            source_backend = target.source,
            confidence = target.confidence,
            dynamic = item.dynamic == true,
            polymorphic = item.polymorphic == true,
            call = item.call_name or item.call,
          }
        end
      end
    end
  end
  return lookup
end

local function external_candidate_nodes(index, source_symbol_id)
  local out = {}
  local seen = {}
  for _, item in ipairs((index.call_resolutions or {})[source_symbol_id] or {}) do
    for _, candidate in ipairs(item.candidates or {}) do
      if not candidate.id and candidate.path and candidate.name then
        local node_id = string.format("fn_external:%s:%s", candidate.path, candidate.name)
        if not seen[node_id] then
          seen[node_id] = true
          out[#out + 1] = {
            node = {
              id = node_id,
              type = "function",
              label = candidate.name,
              path = candidate.path,
              relpath = candidate.path,
              external = true,
            },
            call = item.call_name or item.call,
            source_backend = candidate.source,
            confidence = candidate.confidence,
          }
        end
      end
    end
  end
  return out
end

function M.validate(graph)
  local errors = {}
  local node_ids = {}

  if not graph or type(graph) ~= "table" then
    return {
      ok = false,
      errors = { "graph payload is required" },
      warnings = {},
      node_count = 0,
      edge_count = 0,
    }
  end

  if graph.schema_version ~= "knowledge_graph.v1" then
    errors[#errors + 1] = "unsupported schema version"
  end

  for _, node in ipairs(graph.nodes or {}) do
    if not node.id then
      errors[#errors + 1] = "node missing id"
    else
      node_ids[node.id] = true
    end
    if node.type and not NODE_TYPES[node.type] then
      errors[#errors + 1] = "node has unsupported type: " .. tostring(node.type)
    end
  end

  for _, edge in ipairs(graph.edges or {}) do
    if not edge.source or not node_ids[edge.source] then
      errors[#errors + 1] = "edge source not found: " .. tostring(edge.source)
    end
    if not edge.target or not node_ids[edge.target] then
      errors[#errors + 1] = "edge target not found: " .. tostring(edge.target)
    end
  end

  return {
    ok = #errors == 0,
    errors = errors,
    warnings = {},
    node_count = #(graph.nodes or {}),
    edge_count = #(graph.edges or {}),
  }
end

function M.build(index, opts)
  if not index then
    return nil, "project index unavailable"
  end

  local build_opts = normalize_build_opts(opts)
  local nodes = {}
  local edges = {}
  local node_seen = {}
  local edge_seen = {}
  local edge_type_counts = {}

  local file_node_ids = {}
  local module_node_ids = {}
  local package_node_ids = {}
  local type_node_ids = {}
  local function_node_ids = {}
  local test_node_ids = {}
  local resolution_lookup = resolution_edge_lookup(index)

  for _, symbol in ipairs(index.symbols or {}) do
    local fn_id = "fn:" .. symbol.id
    add_node(nodes, node_seen, {
      id = fn_id,
      type = "function",
      label = symbol.name,
      path = symbol.path,
      relpath = symbol.relpath,
      lang = symbol.lang,
      symbol_kind = symbol.symbol_kind,
      module_id = symbol.module_id,
      package_id = symbol.package_id,
      range = symbol.range,
    })
    function_node_ids[symbol.id] = fn_id

    local file_id = "file:" .. tostring(symbol.relpath or symbol.path)
    file_node_ids[file_id] = true
    add_node(nodes, node_seen, {
      id = file_id,
      type = "file",
      label = symbol.relpath or symbol.path,
      path = symbol.path,
      relpath = symbol.relpath,
    })

    add_edge(edges, edge_seen, {
      type = "defines",
      source = file_id,
      target = fn_id,
    })
    add_edge_count(edge_type_counts, "defines")

    local module_id = "module:" .. tostring(symbol.module_id)
    module_node_ids[module_id] = true
    add_node(nodes, node_seen, {
      id = module_id,
      type = "module",
      label = symbol.module_id,
    })
    add_edge(edges, edge_seen, {
      type = "belongs_to_module",
      source = fn_id,
      target = module_id,
    })
    add_edge_count(edge_type_counts, "belongs_to_module")

    local package_id = "package:" .. tostring(symbol.package_id)
    package_node_ids[package_id] = true
    add_node(nodes, node_seen, {
      id = package_id,
      type = "package",
      label = symbol.package_id,
    })
    add_edge(edges, edge_seen, {
      type = "belongs_to_package",
      source = fn_id,
      target = package_id,
    })
    add_edge_count(edge_type_counts, "belongs_to_package")

    add_edge(edges, edge_seen, {
      type = "contains_module",
      source = package_id,
      target = module_id,
    })
    add_edge_count(edge_type_counts, "contains_module")

    if build_opts.include_types then
      local t_id = type_node_id(symbol)
      if t_id then
        type_node_ids[t_id] = true
        add_node(nodes, node_seen, {
          id = t_id,
          type = "type",
          label = symbol.container,
          path = symbol.path,
          relpath = symbol.relpath,
          module_id = symbol.module_id,
          package_id = symbol.package_id,
        })
        add_edge(edges, edge_seen, edge_record("defines_type", file_id, t_id))
        add_edge_count(edge_type_counts, "defines_type")
        add_edge(edges, edge_seen, edge_record("belongs_to_type", fn_id, t_id))
        add_edge_count(edge_type_counts, "belongs_to_type")
      end
    end

    if build_opts.include_tests and is_test_symbol(symbol) then
      local test_id = "test:" .. symbol.id
      add_node(nodes, node_seen, {
        id = test_id,
        type = "test",
        label = symbol.name,
        path = symbol.path,
        relpath = symbol.relpath,
      })
      test_node_ids[test_id] = true
      add_edge(edges, edge_seen, {
        type = "test_covers",
        source = test_id,
        target = fn_id,
      })
      add_edge_count(edge_type_counts, "test_covers")
    end
  end

  for source_id, targets in pairs(index.outgoing or {}) do
    local source_fn = function_node_ids[source_id]
    if source_fn then
      local source_symbol = index.by_id[source_id]
      local source_is_test = source_symbol and is_test_symbol(source_symbol)
      for _, target_id in ipairs(targets or {}) do
        local target_fn = function_node_ids[target_id]
        if target_fn then
          local meta = (((resolution_lookup or {})[source_id] or {})[target_id]) or {}
          local edge_type = source_is_test and "tests" or "calls"
          add_edge(edges, edge_seen, edge_record(edge_type, source_fn, target_fn, {
            source_backend = meta.source_backend or "index",
            confidence = meta.confidence or "unknown",
            dynamic = meta.dynamic == true,
            polymorphic = meta.polymorphic == true,
            call = meta.call,
          }))
          add_edge_count(edge_type_counts, edge_type)
        end
      end

      if build_opts.include_external then
        for _, ext in ipairs(external_candidate_nodes(index, source_id)) do
          add_node(nodes, node_seen, ext.node)
          add_edge(edges, edge_seen, edge_record("calls_external", source_fn, ext.node.id, {
            source_backend = ext.source_backend or "lsp",
            confidence = ext.confidence or "unknown",
            call = ext.call,
            external = true,
          }))
          add_edge_count(edge_type_counts, "calls_external")
        end
      end
    end
  end

  if build_opts.include_imports then
    local import_graph = index.import_graph or {}
    for file_id, _ in pairs(import_graph.nodes or {}) do
      local source_node = "file:" .. file_id
      add_node(nodes, node_seen, {
        id = source_node,
        type = "file",
        label = file_id,
      })
      for _, dep in ipairs((import_graph.outgoing or {})[file_id] or {}) do
        local target_node = "file:" .. dep
        add_node(nodes, node_seen, {
          id = target_node,
          type = "file",
          label = dep,
        })
        add_edge(edges, edge_seen, edge_record("imports", source_node, target_node, {
          source_backend = "index",
          confidence = "high",
        }))
        add_edge_count(edge_type_counts, "imports")
      end
    end
  end

  local counts = {
    total_nodes = #nodes,
    total_edges = #edges,
    function_nodes = vim.tbl_count(function_node_ids),
    type_nodes = vim.tbl_count(type_node_ids),
    file_nodes = vim.tbl_count(file_node_ids),
    module_nodes = vim.tbl_count(module_node_ids),
    package_nodes = vim.tbl_count(package_node_ids),
    test_nodes = vim.tbl_count(test_node_ids),
    edge_type_counts = edge_type_counts,
  }

  local graph = {
    schema_version = "knowledge_graph.v1",
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    root = index.root,
    nodes = nodes,
    edges = edges,
    counts = counts,
    options = build_opts,
  }

  graph.validation = M.validate(graph)

  return graph, nil
end

function M.write_snapshot(path, graph, opts)
  if not path or path == "" then
    return nil, "snapshot path is required"
  end
  if not graph then
    return nil, "knowledge graph is required"
  end

  local dir = vim.fs.dirname(path)
  if dir and dir ~= "" then
    vim.fn.mkdir(dir, "p")
  end

  local snapshot_opts = normalize_snapshot_opts(opts)
  local bytes = 0

  if snapshot_opts.format == "jsonl" then
    local lines = {}
    local function push_record(record)
      local text = vim.json.encode(record)
      bytes = bytes + #text
      lines[#lines + 1] = text
    end

    push_record({
      record_type = "meta",
      schema_version = graph.schema_version,
      generated_at = graph.generated_at,
      root = graph.root,
      counts = graph.counts,
      options = graph.options,
      validation = graph.validation,
    })
    for _, node in ipairs(graph.nodes or {}) do
      push_record({
        record_type = "node",
        data = node,
      })
    end
    for _, edge in ipairs(graph.edges or {}) do
      push_record({
        record_type = "edge",
        data = edge,
      })
    end
    vim.fn.writefile(lines, path)
  else
    local json
    json = vim.json.encode(graph)
    bytes = #json
    vim.fn.writefile(vim.split(json .. "\n", "\n", { plain = true }), path)
  end

  return {
    path = path,
    bytes = bytes,
    schema_version = graph.schema_version,
    format = snapshot_opts.format,
  }, nil
end

return M
