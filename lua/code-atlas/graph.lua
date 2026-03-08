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

  return {
    root_id = root_id,
    depth_limit = depth_limit,
    direction = direction,
    nodes = nodes,
    adjacency = adjacency,
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

return M
