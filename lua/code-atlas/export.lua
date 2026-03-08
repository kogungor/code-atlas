local M = {}

local FORMAT_ALIASES = {
  dot = "graphviz",
  gv = "graphviz",
  graphviz = "graphviz",
  mermaid = "mermaid",
  mmd = "mermaid",
  json = "json",
}

local EXTENSIONS = {
  graphviz = "dot",
  mermaid = "mmd",
  json = "json",
}

local function normalize_format(value)
  if not value then
    return nil
  end
  return FORMAT_ALIASES[(value or ""):lower()]
end

local function sorted_ids(map)
  local ids = {}
  for id, _ in pairs(map or {}) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

local function escape_graphviz(value)
  local text = tostring(value or "")
  text = text:gsub("\\", "\\\\")
  text = text:gsub('"', '\\"')
  text = text:gsub("\n", "\\n")
  return text
end

local function escape_mermaid(value)
  local text = tostring(value or "")
  text = text:gsub('"', "'")
  text = text:gsub("<", "&lt;")
  text = text:gsub(">", "&gt;")
  return text
end

local function collect_payload(index, subgraph)
  local nodes = {}
  local edges = {}

  for _, node_id in ipairs(sorted_ids(subgraph.nodes)) do
    local symbol = subgraph.nodes[node_id]
    nodes[#nodes + 1] = {
      id = symbol.id,
      name = symbol.name,
      label = string.format("%s\\n%s", symbol.name, symbol.relpath),
      path = symbol.path,
      relpath = symbol.relpath,
      lang = symbol.lang,
      range = symbol.range,
    }
  end

  for _, source_id in ipairs(sorted_ids(subgraph.adjacency)) do
    local children = vim.deepcopy(subgraph.adjacency[source_id] or {})
    table.sort(children)
    for _, target_id in ipairs(children) do
      if subgraph.nodes[source_id] and subgraph.nodes[target_id] then
        edges[#edges + 1] = {
          source = source_id,
          target = target_id,
        }
      end
    end
  end

  return {
    meta = {
      root = index.root,
      generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      direction = subgraph.direction,
      depth_limit = subgraph.depth_limit,
      root_id = subgraph.root_id,
    },
    nodes = nodes,
    edges = edges,
  }
end

local function serialize_graphviz(payload)
  local lines = {
    "digraph CodeAtlas {",
    "  rankdir=LR;",
    "  node [shape=box];",
  }

  local node_var = {}
  for i, node in ipairs(payload.nodes) do
    local var = "n" .. i
    node_var[node.id] = var
    lines[#lines + 1] = string.format('  %s [label="%s"];', var, escape_graphviz(node.label))
  end

  for _, edge in ipairs(payload.edges) do
    local source = node_var[edge.source]
    local target = node_var[edge.target]
    if source and target then
      lines[#lines + 1] = string.format("  %s -> %s;", source, target)
    end
  end

  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end

local function serialize_mermaid(payload)
  local lines = {
    "flowchart LR",
  }

  local node_var = {}
  for i, node in ipairs(payload.nodes) do
    local var = "n" .. i
    node_var[node.id] = var
    local label = escape_mermaid(node.name) .. "<br/>" .. escape_mermaid(node.relpath)
    lines[#lines + 1] = string.format('  %s["%s"]', var, label)
  end

  for _, edge in ipairs(payload.edges) do
    local source = node_var[edge.source]
    local target = node_var[edge.target]
    if source and target then
      lines[#lines + 1] = string.format("  %s --> %s", source, target)
    end
  end

  return table.concat(lines, "\n") .. "\n"
end

local function serialize_json(payload)
  return vim.json.encode(payload) .. "\n"
end

local function serialize_payload(format, payload)
  if format == "graphviz" then
    return serialize_graphviz(payload)
  end
  if format == "mermaid" then
    return serialize_mermaid(payload)
  end
  return serialize_json(payload)
end

local function write_text(path, content)
  local dir = vim.fs.dirname(path)
  if dir and dir ~= "" then
    vim.fn.mkdir(dir, "p")
  end
  vim.fn.writefile(vim.split(content, "\n", { plain = true }), path)
end

function M.default_extension(format)
  return EXTENSIONS[format] or "txt"
end

function M.export_subgraph(index, subgraph, opts)
  opts = opts or {}
  local format = normalize_format(opts.format or "json")
  if not format then
    return nil, "unsupported export format"
  end
  if not index or not subgraph then
    return nil, "index and subgraph are required"
  end

  local payload = collect_payload(index, subgraph)
  local content = serialize_payload(format, payload)
  local path = opts.path

  if not path or path == "" then
    return nil, "export path is required"
  end

  write_text(path, content)

  return {
    format = format,
    path = path,
    node_count = #payload.nodes,
    edge_count = #payload.edges,
  }, nil
end

function M.normalize_format(value)
  return normalize_format(value)
end

return M
