local M = {}

local unpack_fn = table.unpack or unpack

local function format_range(range)
  local sr, sc, er, ec = unpack_fn(range)
  return string.format("%d:%d-%d:%d", sr + 1, sc + 1, er + 1, ec)
end

local function sorted_ids(map)
  local ids = {}
  for id, _ in pairs(map or {}) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  return ids
end

local function compute_degrees(subgraph)
  local in_degree = {}
  local out_degree = {}

  for _, node_id in ipairs(sorted_ids(subgraph.nodes or {})) do
    in_degree[node_id] = 0
    out_degree[node_id] = 0
  end

  for source_id, children in pairs(subgraph.adjacency or {}) do
    out_degree[source_id] = #children
    for _, target_id in ipairs(children or {}) do
      in_degree[target_id] = (in_degree[target_id] or 0) + 1
    end
  end

  return in_degree, out_degree
end

local function hierarchical_layout(subgraph, opts)
  opts = opts or {}
  local spacing_x = tonumber(opts.spacing_x) or 220
  local spacing_y = tonumber(opts.spacing_y) or 90
  local root = subgraph.root_id or subgraph.root

  local depths = {}
  local queue = {}
  local max_depth = 0
  if root then
    depths[root] = 0
    queue[1] = root
  end

  while #queue > 0 do
    local current = table.remove(queue, 1)
    local depth = depths[current] or 0
    max_depth = math.max(max_depth, depth)
    for _, next_id in ipairs(subgraph.adjacency[current] or {}) do
      if depths[next_id] == nil then
        depths[next_id] = depth + 1
        queue[#queue + 1] = next_id
      end
    end
  end

  local layers = {}
  for _, node_id in ipairs(sorted_ids(subgraph.nodes or {})) do
    local depth = depths[node_id]
    if depth == nil then
      depth = max_depth + 1
    end
    layers[depth] = layers[depth] or {}
    layers[depth][#layers[depth] + 1] = node_id
  end

  local nodes = {}
  local bounds = {
    min_x = 0,
    max_x = 0,
    min_y = 0,
    max_y = 0,
  }
  local first = true

  for depth, ids in pairs(layers) do
    table.sort(ids)
    local center_offset = (#ids - 1) * spacing_y / 2
    for i, node_id in ipairs(ids) do
      local x = depth * spacing_x
      local y = (i - 1) * spacing_y - center_offset
      nodes[node_id] = {
        x = x,
        y = y,
        depth = depth,
        layer_index = i,
      }
      if first then
        bounds.min_x, bounds.max_x = x, x
        bounds.min_y, bounds.max_y = y, y
        first = false
      else
        bounds.min_x = math.min(bounds.min_x, x)
        bounds.max_x = math.max(bounds.max_x, x)
        bounds.min_y = math.min(bounds.min_y, y)
        bounds.max_y = math.max(bounds.max_y, y)
      end
    end
  end

  local out_layers = {}
  local layer_keys = {}
  for depth, _ in pairs(layers) do
    layer_keys[#layer_keys + 1] = depth
  end
  table.sort(layer_keys)
  for _, depth in ipairs(layer_keys) do
    out_layers[#out_layers + 1] = {
      depth = depth,
      ids = layers[depth],
    }
  end

  return {
    algorithm = "hierarchical",
    direction = subgraph.direction or "outgoing",
    nodes = nodes,
    layers = out_layers,
    bounds = bounds,
    options = {
      spacing_x = spacing_x,
      spacing_y = spacing_y,
    },
  }
end

local function force_layout(subgraph, opts)
  opts = opts or {}
  local iterations = math.max(1, math.floor(tonumber(opts.iterations) or 24))
  local width = tonumber(opts.width) or 1200
  local height = tonumber(opts.height) or 800
  local damping = tonumber(opts.damping) or 0.85

  local ids = sorted_ids(subgraph.nodes or {})
  local n = #ids
  if n == 0 then
    return {
      algorithm = "force",
      direction = subgraph.direction or "outgoing",
      nodes = {},
      layers = {},
      bounds = { min_x = 0, max_x = 0, min_y = 0, max_y = 0 },
      options = {
        iterations = iterations,
        width = width,
        height = height,
        damping = damping,
      },
    }
  end

  local k = math.sqrt((width * height) / n)
  local radius = math.min(width, height) * 0.35
  local positions = {}
  local velocities = {}
  local index = {}

  for i, id in ipairs(ids) do
    index[id] = i
    local angle = (2 * math.pi * (i - 1)) / n
    positions[id] = {
      x = math.cos(angle) * radius,
      y = math.sin(angle) * radius,
    }
    velocities[id] = { x = 0, y = 0 }
  end

  local edges = {}
  for source_id, children in pairs(subgraph.adjacency or {}) do
    for _, target_id in ipairs(children or {}) do
      if index[source_id] and index[target_id] then
        edges[#edges + 1] = { source_id, target_id }
      end
    end
  end

  local function norm(dx, dy)
    local d2 = dx * dx + dy * dy
    if d2 < 1e-6 then
      return 1e-3
    end
    return math.sqrt(d2)
  end

  for _ = 1, iterations do
    local force = {}
    for _, id in ipairs(ids) do
      force[id] = { x = 0, y = 0 }
    end

    for i = 1, n do
      local a_id = ids[i]
      local a = positions[a_id]
      for j = i + 1, n do
        local b_id = ids[j]
        local b = positions[b_id]
        local dx = a.x - b.x
        local dy = a.y - b.y
        local d = norm(dx, dy)
        local repulse = (k * k) / d
        local fx = (dx / d) * repulse
        local fy = (dy / d) * repulse
        force[a_id].x = force[a_id].x + fx
        force[a_id].y = force[a_id].y + fy
        force[b_id].x = force[b_id].x - fx
        force[b_id].y = force[b_id].y - fy
      end
    end

    for _, edge in ipairs(edges) do
      local a_id = edge[1]
      local b_id = edge[2]
      local a = positions[a_id]
      local b = positions[b_id]
      local dx = b.x - a.x
      local dy = b.y - a.y
      local d = norm(dx, dy)
      local attract = (d * d) / k
      local fx = (dx / d) * attract
      local fy = (dy / d) * attract
      force[a_id].x = force[a_id].x + fx
      force[a_id].y = force[a_id].y + fy
      force[b_id].x = force[b_id].x - fx
      force[b_id].y = force[b_id].y - fy
    end

    for _, id in ipairs(ids) do
      velocities[id].x = (velocities[id].x + force[id].x * 0.01) * damping
      velocities[id].y = (velocities[id].y + force[id].y * 0.01) * damping
      positions[id].x = positions[id].x + velocities[id].x
      positions[id].y = positions[id].y + velocities[id].y
      positions[id].x = math.max(-width / 2, math.min(width / 2, positions[id].x))
      positions[id].y = math.max(-height / 2, math.min(height / 2, positions[id].y))
    end
  end

  local in_degree, out_degree = compute_degrees(subgraph)
  local nodes = {}
  local bounds = {
    min_x = math.huge,
    max_x = -math.huge,
    min_y = math.huge,
    max_y = -math.huge,
  }

  for _, id in ipairs(ids) do
    local pos = positions[id]
    nodes[id] = {
      x = pos.x,
      y = pos.y,
      depth = nil,
      layer_index = nil,
      in_degree = in_degree[id] or 0,
      out_degree = out_degree[id] or 0,
    }
    bounds.min_x = math.min(bounds.min_x, pos.x)
    bounds.max_x = math.max(bounds.max_x, pos.x)
    bounds.min_y = math.min(bounds.min_y, pos.y)
    bounds.max_y = math.max(bounds.max_y, pos.y)
  end

  return {
    algorithm = "force",
    direction = subgraph.direction or "outgoing",
    nodes = nodes,
    layers = {},
    bounds = bounds,
    options = {
      iterations = iterations,
      width = width,
      height = height,
      damping = damping,
    },
  }
end

function M.layout_metadata(subgraph, opts)
  opts = opts or {}
  local algorithm = (opts.algorithm or "hierarchical"):lower()
  if algorithm == "force" or algorithm == "force_directed" then
    return force_layout(subgraph, opts)
  end
  return hierarchical_layout(subgraph, opts)
end

function M.call_graph_lines(func, calls)
  return M.call_graph_document(func, calls).lines
end

function M.call_graph_document(func, calls)
  local lines = {
    "code-atlas",
    "",
    string.format("root: %s [%s]", func.name, func.lang),
    string.format("range: %s", format_range(func.range)),
    "",
    "calls:",
  }
  local line_actions = {}

  if func.target then
    line_actions[3] = {
      target = func.target,
    }
  end

  if not calls or #calls == 0 then
    lines[#lines + 1] = "  └─ (no local calls)"
    return {
      lines = lines,
      line_actions = line_actions,
    }
  end

  for i, call in ipairs(calls) do
    local prefix = "  ├─"
    if i == #calls then
      prefix = "  └─"
    end
    lines[#lines + 1] = string.format("%s %s", prefix, call.name)
    if call.target then
      line_actions[#lines] = {
        target = call.target,
      }
    end
  end

  return {
    lines = lines,
    line_actions = line_actions,
  }
end

local function node_prefix(graph, session, node_name, depth, is_last)
  local has_children = graph.is_expandable(session, node_name, depth)
  local is_open = graph.is_expanded(session, node_name)
  local marker = "[ ]"

  if has_children and is_open then
    marker = "[-]"
  elseif has_children then
    marker = "[+]"
  end

  local branch = is_last and "└─" or "├─"
  return string.format("%s %s", branch, marker)
end

function M.expanded_graph_document(session)
  local graph = require("code-atlas.graph")
  local lines = {
    "code-atlas",
    "",
    string.format("root: %s [%s]", session.root_function.name, session.root_function.lang),
    string.format("range: %s", format_range(session.root_function.range)),
    "",
    "graph:",
  }
  local line_actions = {
    [3] = {
      target = {
        bufnr = session.bufnr,
        row = session.root_function.range[1],
        col = session.root_function.range[2],
      },
      node_name = session.root_function.name,
      depth = 0,
      expandable = graph.is_expandable(session, session.root_function.name, 0),
      expanded = graph.is_expanded(session, session.root_function.name),
    },
  }

  local function append_node(node_name, indent, depth, is_last, path)
    if path[node_name] then
      lines[#lines + 1] = string.format("%s└─ [ ] %s (cycle)", indent, node_name)
      return
    end

    local next_path = vim.deepcopy(path)
    next_path[node_name] = true

    local def = session.definitions[node_name]
    local prefix = node_prefix(graph, session, node_name, depth, is_last)
    lines[#lines + 1] = string.format("%s%s %s", indent, prefix, node_name)

    local line_idx = #lines
    line_actions[line_idx] = {
      node_name = node_name,
      depth = depth,
      expandable = graph.is_expandable(session, node_name, depth),
      expanded = graph.is_expanded(session, node_name),
    }

    if def and def.range then
      line_actions[line_idx].target = {
        bufnr = session.bufnr,
        row = def.range[1],
        col = def.range[2],
      }
    end

    local children = graph.children(session, node_name)
    if #children == 0 then
      return
    end

    if not graph.can_expand_depth(session, depth) then
      return
    end

    if not graph.is_expanded(session, node_name) then
      return
    end

    local child_indent = indent .. (is_last and "   " or "│  ")
    for idx, child in ipairs(children) do
      append_node(child, child_indent, depth + 1, idx == #children, next_path)
    end
  end

  append_node(session.root, "", 0, true, {})

  return {
    lines = lines,
    line_actions = line_actions,
  }
end

function M.project_graph_document(index, subgraph)
  local root_symbol = index.by_id[subgraph.root_id]
  local function symbol_label(symbol)
    return string.format("%s - %s", symbol.name, symbol.relpath or symbol.path)
  end

  local root_label = subgraph.root_id
  if root_symbol then
    root_label = symbol_label(root_symbol)
  end

  local node_count = 0
  local edge_count = 0
  local unresolved_scoped = 0
  for _, _ in pairs(subgraph.nodes or {}) do
    node_count = node_count + 1
  end
  for _, children in pairs(subgraph.adjacency or {}) do
    edge_count = edge_count + #children
  end
  for symbol_id, _ in pairs(subgraph.nodes or {}) do
    for _, item in ipairs(((index.call_resolutions or {})[symbol_id]) or {}) do
      if item.unresolved then
        unresolved_scoped = unresolved_scoped + 1
      end
    end
  end

  local direction = subgraph.direction or "outgoing"
  local relation_label = direction == "incoming" and "callers" or "callees"
  local layout_algo = ((subgraph.layout or {}).algorithm) or "none"
  local backend = subgraph.backend or "index"
  local lsp_client_id = subgraph.lsp_client_id
  local external_filtered = nil
  if subgraph.include_external ~= nil then
    external_filtered = not subgraph.include_external
  end

  local lines = {
    "code-atlas project graph",
    "",
    string.format("root: %s", root_label),
    string.format("mode: %s", relation_label),
    string.format("backend: %s", backend),
    lsp_client_id and string.format("lsp_client_id: %s", tostring(lsp_client_id)) or nil,
    external_filtered ~= nil and string.format("external_filtered: %s", tostring(external_filtered)) or nil,
    string.format("layout: %s", layout_algo),
    string.format("depth_limit: %d", subgraph.depth_limit),
    string.format("nodes: %d, edges: %d", node_count, edge_count),
    string.format("polymorphic_calls: %d", tonumber(subgraph.polymorphic_calls) or 0),
    string.format("unresolved_calls: %d", unresolved_scoped),
    string.format("unresolved_calls_global: %d", index.unresolved_count or 0),
    "",
    string.format("%s:", relation_label),
  }
  lines = vim.tbl_filter(function(value)
    return value ~= nil
  end, lines)
  local line_actions = {}

  if root_symbol then
    local root_line = nil
    for i, line in ipairs(lines) do
      if line == string.format("root: %s", root_label) then
        root_line = i
        break
      end
    end
    line_actions[root_line or 3] = {
      target = {
        path = root_symbol.path,
        row = root_symbol.range[1],
        col = root_symbol.range[2],
      },
    }
  end

  local root_resolutions = ((index.call_resolutions or {})[subgraph.root_id]) or {}
  local resolution_lines = {}
  for _, item in ipairs(root_resolutions) do
    local best = item.best
    local poly_suffix = ""
    if item.polymorphic and item.targets then
      poly_suffix = string.format(" [poly:%d]", #item.targets)
    end
    if best then
      resolution_lines[#resolution_lines + 1] = string.format(
        "  - %s -> %s [%s|%s]%s",
        tostring(item.call_name or item.call),
        tostring(best.name),
        tostring(best.source or "index"),
        tostring(best.confidence or "unknown"),
        poly_suffix
      )
      if item.polymorphic and item.targets then
        for idx, target in ipairs(item.targets) do
          if idx > 1 then
            resolution_lines[#resolution_lines + 1] = string.format(
              "      alt -> %s [%s|%s]",
              tostring(target.name),
              tostring(target.source or "index"),
              tostring(target.confidence or "unknown")
            )
          end
        end
      end
    else
      resolution_lines[#resolution_lines + 1] = string.format("  - %s -> (unresolved)", tostring(item.call_name or item.call))
    end
  end

  if #resolution_lines > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "resolution_candidates:"
    local preview_limit = math.min(8, #resolution_lines)
    for i = 1, preview_limit do
      lines[#lines + 1] = resolution_lines[i]
    end
    if #resolution_lines > preview_limit then
      lines[#lines + 1] = string.format("  ... (%d more)", #resolution_lines - preview_limit)
    end
  end

  local function append_node(symbol_id, indent, is_last, path)
    if path[symbol_id] then
      local symbol = index.by_id[symbol_id]
      lines[#lines + 1] = string.format("%s└─ [ ] %s (cycle)", indent, symbol and symbol_label(symbol) or symbol_id)
      return
    end

    local symbol = index.by_id[symbol_id]
    if not symbol then
      return
    end

    local next_path = vim.deepcopy(path)
    next_path[symbol_id] = true

    local branch = is_last and "└─" or "├─"
    local edge_note = ""
    if path.__parent_id then
      local ann = (((subgraph.edge_annotations or {})[path.__parent_id] or {})[symbol_id])
      if ann and ann.dynamic then
        edge_note = " [dynamic]"
      end
    end
    lines[#lines + 1] = string.format("%s%s %s%s", indent, branch, symbol_label(symbol), edge_note)
    line_actions[#lines] = {
      target = {
        path = symbol.path,
        row = symbol.range[1],
        col = symbol.range[2],
      },
    }

    local children = subgraph.adjacency[symbol_id] or {}
    local child_indent = indent .. (is_last and "   " or "│  ")
    next_path.__parent_id = symbol_id
    for idx, child_id in ipairs(children) do
      append_node(child_id, child_indent, idx == #children, next_path)
    end
  end

  append_node(subgraph.root_id, "", true, {})

  return {
    lines = lines,
    line_actions = line_actions,
  }
end

function M.dependency_graph_document(dep_graph, subgraph, opts)
  opts = opts or {}
  local title = opts.title or "dependency graph"

  local root_node = dep_graph.nodes[subgraph.root_id]
  local root_label = subgraph.root_id
  if root_node then
    root_label = root_node.label
  end

  local direction = subgraph.direction or "outgoing"
  local relation_label = direction == "incoming" and "dependents" or "dependencies"
  local layout_algo = ((subgraph.layout or {}).algorithm) or "none"

  local node_count = 0
  local edge_count = 0
  for _, _ in pairs(subgraph.nodes or {}) do
    node_count = node_count + 1
  end
  for _, children in pairs(subgraph.adjacency or {}) do
    edge_count = edge_count + #children
  end

  local lines = {
    title,
    "",
    string.format("root: %s", root_label),
    string.format("mode: %s", relation_label),
    string.format("layout: %s", layout_algo),
    string.format("depth_limit: %d", subgraph.depth_limit),
    string.format("nodes: %d, edges: %d", node_count, edge_count),
    string.format("summary_nodes: %d, summary_edges: %d", dep_graph.node_count or 0, dep_graph.edge_count or 0),
    "",
    string.format("%s:", relation_label),
  }

  local line_actions = {}
  if root_node and root_node.target then
    line_actions[3] = {
      target = root_node.target,
    }
  end

  local function append_node(node_id, indent, is_last, path)
    if path[node_id] then
      local node = dep_graph.nodes[node_id]
      lines[#lines + 1] = string.format("%s└─ %s (cycle)", indent, node and node.label or node_id)
      return
    end

    local node = dep_graph.nodes[node_id]
    if not node then
      return
    end

    local next_path = vim.deepcopy(path)
    next_path[node_id] = true

    local branch = is_last and "└─" or "├─"
    lines[#lines + 1] = string.format("%s%s %s", indent, branch, node.label)
    if node.target then
      line_actions[#lines] = {
        target = node.target,
      }
    end

    local children = subgraph.adjacency[node_id] or {}
    local child_indent = indent .. (is_last and "   " or "│  ")
    for idx, child_id in ipairs(children) do
      append_node(child_id, child_indent, idx == #children, next_path)
    end
  end

  append_node(subgraph.root_id, "", true, {})

  return {
    lines = lines,
    line_actions = line_actions,
  }
end

function M.dead_code_document(report)
  local lines = {
    "code-atlas dead code report",
    "",
    string.format("total_symbols: %d", report.total_symbols or 0),
    string.format("dead_count: %d", report.dead_count or 0),
    "",
    "dead_symbols:",
  }
  local line_actions = {}

  if not report.dead or #report.dead == 0 then
    lines[#lines + 1] = "  (none)"
    return {
      lines = lines,
      line_actions = line_actions,
    }
  end

  for _, symbol in ipairs(report.dead) do
    lines[#lines + 1] = string.format("  - %s - %s", symbol.name, symbol.relpath or symbol.path)
    line_actions[#lines] = {
      target = {
        path = symbol.path,
        row = symbol.range[1],
        col = symbol.range[2],
      },
    }
  end

  return {
    lines = lines,
    line_actions = line_actions,
  }
end

function M.impact_document(report)
  local lines = {
    "code-atlas impact analysis",
    "",
    string.format("root: %s - %s", report.root.name, report.root.relpath or report.root.path),
    string.format("max_depth: %d", report.max_depth or 0),
    string.format("direct_callers: %d", #(report.direct_callers or {})),
    string.format("impacted_symbols: %d", #(report.impacted_symbols or {})),
    string.format("impacted_modules: %d", #(report.impacted_modules or {})),
    string.format("impacted_packages: %d", #(report.impacted_packages or {})),
    string.format("impacted_tests: %d", #(report.impacted_tests or {})),
    "",
    "callers:",
  }
  local line_actions = {
    [3] = {
      target = {
        path = report.root.path,
        row = report.root.range[1],
        col = report.root.range[2],
      },
    },
  }

  if not report.impacted_symbols or #report.impacted_symbols == 0 then
    lines[#lines + 1] = "  (none)"
  else
    for _, symbol in ipairs(report.impacted_symbols) do
      lines[#lines + 1] = string.format("  - %s - %s", symbol.name, symbol.relpath or symbol.path)
      line_actions[#lines] = {
        target = {
          path = symbol.path,
          row = symbol.range[1],
          col = symbol.range[2],
        },
      }
    end
  end

  if report.impacted_modules and #report.impacted_modules > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "modules:"
    for _, module_id in ipairs(report.impacted_modules) do
      lines[#lines + 1] = "  - " .. module_id
    end
  end

  if report.impacted_tests and #report.impacted_tests > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "tests:"
    for _, symbol in ipairs(report.impacted_tests) do
      lines[#lines + 1] = string.format("  - %s - %s", symbol.name, symbol.relpath or symbol.path)
    end
  end

  return {
    lines = lines,
    line_actions = line_actions,
  }
end

return M
