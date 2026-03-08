local M = {}

local function normalize_depth_limit(value)
  local n = tonumber(value)
  if not n then
    return 2
  end
  n = math.floor(n)
  if n < 0 then
    return 0
  end
  return n
end

local function dedupe(items)
  local seen = {}
  local out = {}
  for _, item in ipairs(items) do
    if not seen[item] then
      seen[item] = true
      out[#out + 1] = item
    end
  end
  return out
end

local function build_adjacency(bufnr, definitions)
  local treesitter = require("code-atlas.treesitter")
  local adjacency = {}

  for name, _ in pairs(definitions) do
    local calls, err = treesitter.get_local_calls_for_function(bufnr, name)
    if calls and not err then
      local children = {}
      for _, call in ipairs(calls) do
        local def = treesitter.find_local_function_definition(bufnr, call.name)
        if def and def.name then
          children[#children + 1] = def.name
        end
      end
      adjacency[name] = dedupe(children)
    else
      adjacency[name] = {}
    end
  end

  return adjacency
end

function M.new_session(bufnr, root_function, opts)
  local treesitter = require("code-atlas.treesitter")
  opts = opts or {}

  local functions, err = treesitter.list_local_functions(bufnr)
  if not functions then
    return nil, err
  end

  local definitions = {}
  for _, fn in ipairs(functions) do
    definitions[fn.name] = fn
  end

  local adjacency = build_adjacency(bufnr, definitions)
  local session = {
    bufnr = bufnr,
    root = root_function.name,
    root_function = root_function,
    depth_limit = normalize_depth_limit(opts.depth_limit),
    definitions = definitions,
    adjacency = adjacency,
    expanded = {
      [root_function.name] = true,
    },
  }

  return session, nil
end

function M.children(session, node_name)
  return session.adjacency[node_name] or {}
end

function M.can_expand_depth(session, depth)
  return depth < session.depth_limit
end

function M.is_expandable(session, node_name, depth)
  depth = depth or 0
  return M.can_expand_depth(session, depth) and #M.children(session, node_name) > 0
end

function M.is_expanded(session, node_name)
  return session.expanded[node_name] == true
end

function M.expand(session, node_name, depth)
  depth = depth or 0
  if M.is_expandable(session, node_name, depth) then
    session.expanded[node_name] = true
  end
end

function M.collapse(session, node_name)
  session.expanded[node_name] = false
end

function M.project_subgraph(index, root_id, opts)
  opts = opts or {}
  local depth_limit = math.max(0, math.floor(tonumber(opts.depth_limit) or 2))
  local direction = opts.direction or "outgoing"
  local edges = direction == "incoming" and index.incoming or index.outgoing
  local nodes = {}
  local adjacency = {}
  local edge_annotations = {}
  local queue = {
    { id = root_id, depth = 0 },
  }
  local seen = {}

  while #queue > 0 do
    local current = table.remove(queue, 1)
    local symbol = index.by_id[current.id]
    if symbol then
      nodes[current.id] = symbol
      adjacency[current.id] = adjacency[current.id] or {}

      if current.depth < depth_limit and not seen[current.id .. ":" .. current.depth] then
        seen[current.id .. ":" .. current.depth] = true
        for _, child_id in ipairs(edges[current.id] or {}) do
          adjacency[current.id][#adjacency[current.id] + 1] = child_id
          queue[#queue + 1] = {
            id = child_id,
            depth = current.depth + 1,
          }
        end
      end
    end
  end

  local polymorphic_calls = 0
  local call_resolutions = index.call_resolutions or {}
  for source_id, _ in pairs(nodes) do
    for _, entry in ipairs(call_resolutions[source_id] or {}) do
      if entry.polymorphic and (entry.targets and #entry.targets > 1) then
        local linked = 0
        edge_annotations[source_id] = edge_annotations[source_id] or {}
        for _, target in ipairs(entry.targets) do
          if target.id and nodes[target.id] then
            linked = linked + 1
            edge_annotations[source_id][target.id] = edge_annotations[source_id][target.id] or {
              dynamic = true,
              polymorphic = true,
              calls = {},
            }
            edge_annotations[source_id][target.id].calls[#edge_annotations[source_id][target.id].calls + 1] = entry.call_name
              or entry.call
              or "<call>"
          end
        end
        if linked > 1 then
          polymorphic_calls = polymorphic_calls + 1
        end
      end
    end
  end

  return {
    root_id = root_id,
    depth_limit = depth_limit,
    direction = direction,
    nodes = nodes,
    adjacency = adjacency,
    edge_annotations = edge_annotations,
    polymorphic_calls = polymorphic_calls,
  }
end

function M.dependency_subgraph(dep_graph, root_id, opts)
  opts = opts or {}
  local depth_limit = math.max(0, math.floor(tonumber(opts.depth_limit) or 2))
  local direction = opts.direction or "outgoing"
  local edges = direction == "incoming" and dep_graph.incoming or dep_graph.outgoing
  local nodes = {}
  local adjacency = {}
  local queue = {
    { id = root_id, depth = 0 },
  }
  local seen = {}

  while #queue > 0 do
    local current = table.remove(queue, 1)
    local node = dep_graph.nodes[current.id]
    if node then
      nodes[current.id] = node
      adjacency[current.id] = adjacency[current.id] or {}

      if current.depth < depth_limit and not seen[current.id .. ":" .. current.depth] then
        seen[current.id .. ":" .. current.depth] = true
        for _, child_id in ipairs(edges[current.id] or {}) do
          adjacency[current.id][#adjacency[current.id] + 1] = child_id
          queue[#queue + 1] = {
            id = child_id,
            depth = current.depth + 1,
          }
        end
      end
    end
  end

  return {
    root_id = root_id,
    depth_limit = depth_limit,
    direction = direction,
    nodes = nodes,
    adjacency = adjacency,
  }
end

function M.filter_project_subgraph(subgraph, predicate, opts)
  opts = opts or {}
  local keep_root = opts.keep_root ~= false
  local root_id = subgraph.root_id

  local keep = {}
  for id, node in pairs(subgraph.nodes or {}) do
    if predicate(id, node) then
      keep[id] = true
    end
  end
  if keep_root and root_id then
    keep[root_id] = true
  end

  local filtered_nodes = {}
  for id, node in pairs(subgraph.nodes or {}) do
    if keep[id] then
      filtered_nodes[id] = node
    end
  end

  local filtered_adjacency = {}
  for source_id, children in pairs(subgraph.adjacency or {}) do
    if keep[source_id] then
      filtered_adjacency[source_id] = filtered_adjacency[source_id] or {}
      for _, target_id in ipairs(children or {}) do
        if keep[target_id] then
          filtered_adjacency[source_id][#filtered_adjacency[source_id] + 1] = target_id
        end
      end
    end
  end

  if opts.connected_to_root ~= false and root_id and filtered_nodes[root_id] then
    local reachable = {}
    local queue = { root_id }
    reachable[root_id] = true
    while #queue > 0 do
      local current = table.remove(queue, 1)
      for _, child in ipairs(filtered_adjacency[current] or {}) do
        if not reachable[child] then
          reachable[child] = true
          queue[#queue + 1] = child
        end
      end
    end

    for id, _ in pairs(filtered_nodes) do
      if not reachable[id] then
        filtered_nodes[id] = nil
        filtered_adjacency[id] = nil
      end
    end

    for source_id, children in pairs(filtered_adjacency) do
      local next_children = {}
      for _, child in ipairs(children or {}) do
        if reachable[child] then
          next_children[#next_children + 1] = child
        end
      end
      filtered_adjacency[source_id] = next_children
    end
  end

  local edge_annotations = {}
  local polymorphic_calls = 0
  for source_id, targets in pairs((subgraph.edge_annotations or {})) do
    if filtered_nodes[source_id] then
      for target_id, ann in pairs(targets or {}) do
        if filtered_nodes[target_id] then
          edge_annotations[source_id] = edge_annotations[source_id] or {}
          edge_annotations[source_id][target_id] = ann
          if ann.polymorphic and ann.calls and #ann.calls > 0 then
            polymorphic_calls = polymorphic_calls + 1
          end
        end
      end
    end
  end

  return {
    root_id = subgraph.root_id,
    depth_limit = subgraph.depth_limit,
    direction = subgraph.direction,
    nodes = filtered_nodes,
    adjacency = filtered_adjacency,
    edge_annotations = edge_annotations,
    polymorphic_calls = polymorphic_calls,
    backend = subgraph.backend,
    lsp_client_id = subgraph.lsp_client_id,
    include_external = subgraph.include_external,
  }
end

return M
