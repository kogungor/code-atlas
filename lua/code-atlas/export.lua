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

local function collect_payload(index, subgraph, layout)
  local nodes = {}
  local edges = {}

  for _, node_id in ipairs(sorted_ids(subgraph.nodes)) do
    local symbol = subgraph.nodes[node_id]
    local pos = (layout.nodes or {})[symbol.id] or {}
    nodes[#nodes + 1] = {
      id = symbol.id,
      name = symbol.name,
      label = string.format("%s\\n%s", symbol.name, symbol.relpath),
      path = symbol.path,
      relpath = symbol.relpath,
      lang = symbol.lang,
      range = symbol.range,
      layout = {
        x = pos.x,
        y = pos.y,
        depth = pos.depth,
        layer_index = pos.layer_index,
      },
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
      layout_algorithm = layout.algorithm,
    },
    nodes = nodes,
    edges = edges,
    layout = layout,
  }
end

local function serialize_graphviz(payload)
  local lines = {
    "digraph CodeAtlas {",
    "  // layout: " .. tostring(payload.meta.layout_algorithm),
    "  rankdir=LR;",
    "  node [shape=box];",
  }

  if payload.meta.layout_algorithm == "force" then
    lines[#lines + 1] = "  layout=neato;"
    lines[#lines + 1] = "  overlap=false;"
    lines[#lines + 1] = "  splines=true;"
  end

  local node_var = {}
  for i, node in ipairs(payload.nodes) do
    local var = "n" .. i
    node_var[node.id] = var
    local attrs = { string.format('label="%s"', escape_graphviz(node.label)) }
    if payload.meta.layout_algorithm == "force" and node.layout and node.layout.x and node.layout.y then
      attrs[#attrs + 1] = string.format('pos="%.2f,%.2f!"', tonumber(node.layout.x), tonumber(node.layout.y))
      attrs[#attrs + 1] = "pin=true"
    end
    lines[#lines + 1] = string.format("  %s [%s];", var, table.concat(attrs, ", "))
  end

  if payload.meta.layout_algorithm == "hierarchical" and payload.layout and payload.layout.layers then
    for _, layer in ipairs(payload.layout.layers) do
      local same_rank = {}
      for _, id in ipairs(layer.ids or {}) do
        local var = node_var[id]
        if var then
          same_rank[#same_rank + 1] = var
        end
      end
      if #same_rank > 1 then
        lines[#lines + 1] = string.format("  { rank=same; %s; }", table.concat(same_rank, "; "))
      end
    end
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
    payload.meta.layout_algorithm == "force" and "flowchart TD" or "flowchart LR",
    "%% layout: " .. tostring(payload.meta.layout_algorithm),
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
  local render = require("code-atlas.render")
  local format = normalize_format(opts.format or "json")
  if not format then
    return nil, "unsupported export format"
  end
  if not index or not subgraph then
    return nil, "index and subgraph are required"
  end

  local layout = subgraph.layout
  if not layout then
    layout = render.layout_metadata(subgraph, {
      algorithm = opts.layout_algorithm,
      iterations = opts.layout_iterations,
    })
  end

  local payload = collect_payload(index, subgraph, layout)
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
