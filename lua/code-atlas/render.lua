local M = {}

local unpack_fn = table.unpack or unpack

local function format_range(range)
  local sr, sc, er, ec = unpack_fn(range)
  return string.format("%d:%d-%d:%d", sr + 1, sc + 1, er + 1, ec)
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
  for _, _ in pairs(subgraph.nodes or {}) do
    node_count = node_count + 1
  end
  for _, children in pairs(subgraph.adjacency or {}) do
    edge_count = edge_count + #children
  end

  local direction = subgraph.direction or "outgoing"
  local relation_label = direction == "incoming" and "callers" or "callees"

  local lines = {
    "code-atlas project graph",
    "",
    string.format("root: %s", root_label),
    string.format("mode: %s", relation_label),
    string.format("depth_limit: %d", subgraph.depth_limit),
    string.format("nodes: %d, edges: %d", node_count, edge_count),
    string.format("unresolved_calls: %d", index.unresolved_count or 0),
    "",
    string.format("%s:", relation_label),
  }
  local line_actions = {}

  if root_symbol then
    line_actions[3] = {
      target = {
        path = root_symbol.path,
        row = root_symbol.range[1],
        col = root_symbol.range[2],
      },
    }
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
    lines[#lines + 1] = string.format("%s%s %s", indent, branch, symbol_label(symbol))
    line_actions[#lines] = {
      target = {
        path = symbol.path,
        row = symbol.range[1],
        col = symbol.range[2],
      },
    }

    local children = subgraph.adjacency[symbol_id] or {}
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
