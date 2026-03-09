local M = {
  _is_setup = false,
}

local function current_ui_mode()
  local config = require("code-atlas.config").get()
  local mode = ((config.ui or {}).mode or "tree"):lower()
  if mode ~= "tree" and mode ~= "ascii" then
    return "tree"
  end
  return mode
end

local function build_ascii_doc(bufnr, func)
  local treesitter = require("code-atlas.treesitter")
  local render = require("code-atlas.render")

  local calls, err = treesitter.get_local_calls_for_function(bufnr, func.name)
  if not calls then
    return nil, err
  end

  local graph_func = vim.tbl_extend("force", func, {
    target = {
      bufnr = bufnr,
      row = func.range[1],
      col = func.range[2],
    },
  })

  local graph_calls = {}
  for _, call in ipairs(calls) do
    local definition = treesitter.find_local_function_definition(bufnr, call.name)
    local target = {
      bufnr = bufnr,
      row = call.range[1],
      col = call.range[2],
    }
    if definition and definition.range then
      target = {
        bufnr = bufnr,
        row = definition.range[1],
        col = definition.range[2],
      }
    end

    graph_calls[#graph_calls + 1] = vim.tbl_extend("force", call, {
      target = target,
    })
  end

  return render.call_graph_document(graph_func, graph_calls), nil
end

local function open_graph_for_function(bufnr, source_win, func)
  local graph = require("code-atlas.graph")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")
  local config = require("code-atlas.config").get()

  if current_ui_mode() == "ascii" then
    local doc, ascii_err = build_ascii_doc(bufnr, func)
    if not doc then
      vim.notify("code-atlas: " .. tostring(ascii_err), vim.log.levels.WARN)
      return
    end

    window.open(doc.lines, {
      title = " code-atlas ascii ",
      source_win = source_win,
      source_buf = bufnr,
      line_actions = doc.line_actions,
    })
    return
  end

  local session, session_err = graph.new_session(bufnr, func, {
    depth_limit = config.depth_limit,
  })
  if not session then
    vim.notify("code-atlas: " .. session_err, vim.log.levels.WARN)
    return
  end

  local function redraw()
    local doc = render.expanded_graph_document(session)
    window.open(doc.lines, {
      title = " code-atlas call graph ",
      source_win = source_win,
      source_buf = bufnr,
      line_actions = doc.line_actions,
      on_expand = function(node_name, depth)
        graph.expand(session, node_name, depth)
        redraw()
      end,
      on_collapse = function(node_name)
        graph.collapse(session, node_name)
        redraw()
      end,
      on_refresh = function()
        redraw()
      end,
    })
  end

  redraw()
end

local function run_call_graph()
  local treesitter = require("code-atlas.treesitter")
  local bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local func, err = treesitter.get_current_function(bufnr)

  if not func then
    vim.notify("code-atlas: " .. err, vim.log.levels.WARN)
    return
  end

  open_graph_for_function(bufnr, source_win, func)
end

function M.run()
  run_call_graph()
end

function M.run_for_function_name(function_name, bufnr)
  local treesitter = require("code-atlas.treesitter")
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local func, err = treesitter.find_local_function_definition(bufnr, function_name)
  if not func then
    vim.notify("code-atlas: " .. err .. " (" .. tostring(function_name) .. ")", vim.log.levels.WARN)
    return
  end

  local source_win = vim.api.nvim_get_current_win()
  open_graph_for_function(bufnr, source_win, func)
end

function M.pick_with_telescope()
  local ok_telescope, telescope = pcall(require, "telescope")
  if not ok_telescope then
    vim.notify("code-atlas: telescope.nvim is required for :CodeAtlasPick", vim.log.levels.WARN)
    return
  end

  local ok_load = pcall(telescope.load_extension, "code_atlas")
  if not ok_load then
    vim.notify("code-atlas: failed to load telescope extension 'code_atlas'", vim.log.levels.WARN)
    return
  end

  local ok_ext, ext = pcall(function()
    return telescope.extensions.code_atlas
  end)
  if not ok_ext or not ext or not ext.functions then
    vim.notify("code-atlas: telescope extension 'code_atlas' is unavailable", vim.log.levels.WARN)
    return
  end

  ext.functions()
end

function M.build_project_index(opts)
  opts = opts or {}
  local config = require("code-atlas.config").get()
  if opts.resolution == nil then
    opts.resolution = vim.deepcopy(config.resolution or {})
  end

  local index, err = require("code-atlas.index").build(opts)
  if not index then
    vim.notify("code-atlas: failed to build project index: " .. tostring(err), vim.log.levels.ERROR)
    return nil, err
  end

  vim.notify(
    string.format(
      "code-atlas: indexed %d symbols across %d files",
      index.symbol_count,
      index.files_indexed
    ),
    vim.log.levels.INFO
  )

  return index, nil
end

function M.refresh_project_index()
  local config = require("code-atlas.config").get()
  local index, err = require("code-atlas.index").refresh({
    resolution = vim.deepcopy(config.resolution or {}),
  })
  if not index then
    vim.notify("code-atlas: failed to refresh project index: " .. tostring(err), vim.log.levels.ERROR)
    return nil, err
  end
  return index, nil
end

local function run_project_graph(direction)
  local index_mod = require("code-atlas.index")
  local graph = require("code-atlas.graph")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")
  local config = require("code-atlas.config").get()

  if ((config.lsp or {}).prefer_call_hierarchy) == true then
    local used_lsp = M.run_lsp_call_graph(direction, { silent = true })
    if used_lsp then
      return
    end
  end

  local index = index_mod.get()
  if not index then
    local built = M.build_project_index({ root = vim.fn.getcwd() })
    index = built
  end

  if not index then
    vim.notify("code-atlas: project index is unavailable", vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local root_symbol = index_mod.find_symbol_at(index, path, row, col)
  if not root_symbol then
    vim.notify("code-atlas: no indexed function under cursor", vim.log.levels.WARN)
    return
  end

  local function lsp_probe_positions(symbol)
    local positions = {
      { row = row, col = col },
      { row = row, col = 0 },
    }

    local function add_position(r, c)
      if r == nil or c == nil then
        return
      end
      for _, pos in ipairs(positions) do
        if pos.row == r and pos.col == c then
          return
        end
      end
      positions[#positions + 1] = { row = r, col = c }
    end

    if symbol and symbol.range then
      add_position(symbol.range[1], symbol.range[2])
      add_position(symbol.range[1], 0)
      local symbol_name = symbol.short_name or symbol.name
      if symbol_name and symbol_name ~= "" then
        local line_text = vim.api.nvim_buf_get_lines(bufnr, symbol.range[1], symbol.range[1] + 1, false)[1] or ""
        local name_start = line_text:find(symbol_name, 1, true)
        if name_start then
          add_position(symbol.range[1], name_start - 1)
        end
      end
    end

    return positions
  end

  local mixed_source_merge = false
  if direction == "outgoing" and ((config.lsp or {}).enabled ~= false) then
    local lsp = require("code-atlas.lsp")
    if lsp.is_available(bufnr) then
      local result, lsp_err = lsp.outgoing_candidates_at_cursor(bufnr, {
        timeout_ms = (config.lsp or {}).timeout_ms,
        include_external = (config.lsp or {}).include_external,
        root = vim.fn.getcwd(),
        positions = lsp_probe_positions(root_symbol),
      })
      if result and result.candidates and #result.candidates > 0 then
        mixed_source_merge = index_mod.merge_lsp_candidates(index, root_symbol.id, result.candidates) == true
      elseif lsp_err and (config.lsp or {}).prefer_call_hierarchy == true then
        vim.notify("code-atlas: lsp candidate merge skipped: " .. tostring(lsp_err), vim.log.levels.DEBUG)
      end
    end
  end

  local subgraph = graph.project_subgraph(index, root_symbol.id, {
    depth_limit = config.depth_limit,
    direction = direction,
  })
  if mixed_source_merge then
    subgraph.backend = "mixed(index+lsp)"
  end
  subgraph.layout = render.layout_metadata(subgraph, {
    algorithm = ((config.layout or {}).algorithm) or "hierarchical",
    spacing_x = (config.layout or {}).spacing_x,
    spacing_y = (config.layout or {}).spacing_y,
    iterations = (config.layout or {}).force_iterations,
  })
  local doc = render.project_graph_document(index, subgraph)

  local title = direction == "incoming" and " code-atlas reverse graph " or " code-atlas project graph "
  window.open(doc.lines, {
    title = title,
    source_win = source_win,
    source_buf = bufnr,
    line_actions = doc.line_actions,
  })
end

function M.run_project_call_graph()
  run_project_graph("outgoing")
end

function M.run_project_reverse_call_graph()
  run_project_graph("incoming")
end

function M.run_lsp_call_graph(direction, opts)
  opts = opts or {}
  direction = direction or "outgoing"

  local lsp = require("code-atlas.lsp")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")
  local config = require("code-atlas.config").get()
  local lsp_cfg = config.lsp or {}

  if lsp_cfg.enabled == false then
    if not opts.silent then
      vim.notify("code-atlas: lsp call hierarchy is disabled in config", vim.log.levels.WARN)
    end
    return false
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  if not lsp.is_available(bufnr) then
    if not opts.silent then
      vim.notify("code-atlas: no lsp client attached", vim.log.levels.WARN)
    end
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local positions = {
    { row = cursor[1] - 1, col = cursor[2] },
    { row = cursor[1] - 1, col = 0 },
  }

  local function add_position(row, col)
    if row == nil or col == nil then
      return
    end
    for _, pos in ipairs(positions) do
      if pos.row == row and pos.col == col then
        return
      end
    end
    positions[#positions + 1] = { row = row, col = col }
  end

  local index_mod = require("code-atlas.index")
  local index = index_mod.get()
  if not index then
    index = M.build_project_index({ root = vim.fn.getcwd() })
  end
  if index then
    local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
    local symbol = index_mod.find_symbol_at(index, path, cursor[1] - 1, cursor[2])
    if symbol and symbol.range then
      add_position(symbol.range[1], symbol.range[2])
      add_position(symbol.range[1], 0)

      if symbol.name and symbol.name ~= "" then
        local line_text = vim.api.nvim_buf_get_lines(bufnr, symbol.range[1], symbol.range[1] + 1, false)[1] or ""
        local name_start = line_text:find(symbol.name, 1, true)
        if name_start then
          add_position(symbol.range[1], name_start - 1)
        end
      end
    end
  end

  local subgraph, err = lsp.call_hierarchy_subgraph(bufnr, {
    direction = direction,
    depth_limit = config.depth_limit,
    timeout_ms = lsp_cfg.timeout_ms,
    include_external = lsp_cfg.include_external,
    root = vim.fn.getcwd(),
    positions = positions,
  })
  if not subgraph then
    if not opts.silent then
      local msg = tostring(err)
      if msg:find("not supported", 1, true) then
        vim.notify(
          "code-atlas: current LSP does not support call hierarchy. Use :CodeAtlasProjectGraph / :CodeAtlasProjectReverseGraph for index-based graph.",
          vim.log.levels.WARN
        )
      elseif msg:find("no call hierarchy item", 1, true) then
        vim.notify(
          "code-atlas: LSP call hierarchy returned no symbol at cursor. Try placing cursor on function name/declaration and retry.",
          vim.log.levels.WARN
        )
      else
        vim.notify("code-atlas: lsp call hierarchy failed: " .. msg, vim.log.levels.WARN)
      end
    end
    return false
  end

  subgraph.layout = render.layout_metadata(subgraph, {
    algorithm = ((config.layout or {}).algorithm) or "hierarchical",
    spacing_x = (config.layout or {}).spacing_x,
    spacing_y = (config.layout or {}).spacing_y,
    iterations = (config.layout or {}).force_iterations,
  })

  local lsp_index = {
    by_id = subgraph.nodes,
    unresolved_count = 0,
  }

  local doc = render.project_graph_document(lsp_index, subgraph)
  local title = direction == "incoming" and " code-atlas lsp reverse graph " or " code-atlas lsp graph "

  window.open(doc.lines, {
    title = title,
    source_win = source_win,
    source_buf = bufnr,
    line_actions = doc.line_actions,
  })

  return true
end

function M.show_lsp_debug()
  local lsp = require("code-atlas.lsp")
  local window = require("code-atlas.window")

  local bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))

  local lines = {
    "code-atlas lsp debug",
    "",
    "buffer: " .. (path ~= "" and path or "[No Name]"),
    "",
    "attached_clients:",
  }

  local clients = lsp.client_debug_info(bufnr)
  if #clients == 0 then
    lines[#lines + 1] = "  (none)"
  else
    for _, client in ipairs(clients) do
      lines[#lines + 1] = string.format(
        "  - %s(id=%s) prepare=%s incoming=%s outgoing=%s encoding=%s",
        tostring(client.name),
        tostring(client.id),
        tostring(client.supports_prepare),
        tostring(client.supports_incoming),
        tostring(client.supports_outgoing),
        tostring(client.offset_encoding)
      )
      if client.roots and #client.roots > 0 then
        for _, root in ipairs(client.roots) do
          lines[#lines + 1] = "      root: " .. root
        end
      end
    end
  end

  local last = lsp.get_last_debug()
  lines[#lines + 1] = ""
  lines[#lines + 1] = "last_lsp_graph_run:"
  if not last then
    lines[#lines + 1] = "  (none)"
  else
    lines[#lines + 1] = "  timestamp: " .. tostring(last.timestamp)
    lines[#lines + 1] = "  direction: " .. tostring(last.direction)
    lines[#lines + 1] = "  depth_limit: " .. tostring(last.depth_limit)
    lines[#lines + 1] = "  include_external: " .. tostring(last.include_external)
    lines[#lines + 1] = "  selected_client_id: " .. tostring(last.selected_client_id)
    lines[#lines + 1] = "  root_item: " .. tostring(last.root_item)
    lines[#lines + 1] = "  node_count: " .. tostring(last.node_count)
    lines[#lines + 1] = "  edge_count: " .. tostring(last.edge_count)
    if last.error then
      lines[#lines + 1] = "  error: " .. tostring(last.error)
    end
    if last.roots and #last.roots > 0 then
      lines[#lines + 1] = "  roots:"
      for _, root in ipairs(last.roots) do
        lines[#lines + 1] = "    - " .. root
      end
    end
  end

  window.open(lines, {
    title = " code-atlas lsp debug ",
    source_win = source_win,
    source_buf = bufnr,
    line_actions = {},
  })
end

function M.run_module_dependency_graph(level)
  level = level or "module"
  local index_mod = require("code-atlas.index")
  local graph = require("code-atlas.graph")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")
  local config = require("code-atlas.config").get()

  local index = index_mod.get()
  if not index then
    index = M.build_project_index({ root = vim.fn.getcwd() })
  end
  if not index then
    vim.notify("code-atlas: project index is unavailable", vim.log.levels.ERROR)
    return
  end

  local dep_graph = level == "package" and index_mod.package_graph(index) or index_mod.module_graph(index)
  if not dep_graph then
    vim.notify("code-atlas: dependency graph is unavailable", vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local symbol = index_mod.find_symbol_at(index, path, row, col)
  if not symbol then
    vim.notify("code-atlas: no indexed function under cursor", vim.log.levels.WARN)
    return
  end

  local root_id = level == "package" and symbol.package_id or symbol.module_id
  local subgraph = graph.dependency_subgraph(dep_graph, root_id, {
    depth_limit = config.depth_limit,
    direction = "outgoing",
  })
  subgraph.layout = render.layout_metadata(subgraph, {
    algorithm = ((config.layout or {}).algorithm) or "hierarchical",
    spacing_x = (config.layout or {}).spacing_x,
    spacing_y = (config.layout or {}).spacing_y,
    iterations = (config.layout or {}).force_iterations,
  })
  local title = level == "package" and "code-atlas package graph" or "code-atlas module graph"
  local doc = render.dependency_graph_document(dep_graph, subgraph, {
    title = title,
  })

  window.open(doc.lines, {
    title = " code-atlas dependency graph ",
    source_win = source_win,
    source_buf = bufnr,
    line_actions = doc.line_actions,
  })
end

function M.run_import_graph(direction)
  direction = direction or "outgoing"
  local index_mod = require("code-atlas.index")
  local graph = require("code-atlas.graph")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")
  local config = require("code-atlas.config").get()

  local index = index_mod.get()
  if not index then
    index = M.build_project_index({ root = vim.fn.getcwd() })
  end
  if not index then
    vim.notify("code-atlas: project index is unavailable", vim.log.levels.ERROR)
    return
  end

  local import_graph = index_mod.import_graph(index)
  if not import_graph then
    vim.notify("code-atlas: import graph is unavailable", vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local file_path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  local root = index.root
  local relpath = file_path

  if file_path:sub(1, #root) == root then
    relpath = file_path:sub(#root + 2)
  end

  if not import_graph.nodes[relpath] then
    vim.notify("code-atlas: current file is not in import graph", vim.log.levels.WARN)
    return
  end

  local subgraph = graph.dependency_subgraph(import_graph, relpath, {
    depth_limit = config.depth_limit,
    direction = direction,
  })
  subgraph.layout = render.layout_metadata(subgraph, {
    algorithm = ((config.layout or {}).algorithm) or "hierarchical",
    spacing_x = (config.layout or {}).spacing_x,
    spacing_y = (config.layout or {}).spacing_y,
    iterations = (config.layout or {}).force_iterations,
  })

  local title = direction == "incoming" and "code-atlas reverse import graph" or "code-atlas import graph"
  local doc = render.dependency_graph_document(import_graph, subgraph, {
    title = title,
  })

  window.open(doc.lines, {
    title = " code-atlas import graph ",
    source_win = source_win,
    source_buf = bufnr,
    line_actions = doc.line_actions,
  })
end

function M.run_dead_code_detection()
  local index_mod = require("code-atlas.index")
  local analysis = require("code-atlas.analysis")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")

  local index = index_mod.get()
  if not index then
    index = M.build_project_index({ root = vim.fn.getcwd() })
  end

  if not index then
    vim.notify("code-atlas: project index is unavailable", vim.log.levels.ERROR)
    return
  end

  local report, err = analysis.detect_dead_code(index, {
    ignore_tests = true,
    ignore_entrypoints = true,
    ignore_path_prefixes = {
      "tests/",
      "playground/",
    },
  })
  if not report then
    vim.notify("code-atlas: dead code analysis failed: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local doc = render.dead_code_document(report)

  window.open(doc.lines, {
    title = " code-atlas dead code ",
    source_win = source_win,
    source_buf = bufnr,
    line_actions = doc.line_actions,
  })
end

function M.run_impact_analysis()
  local index_mod = require("code-atlas.index")
  local analysis = require("code-atlas.analysis")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")
  local config = require("code-atlas.config").get()

  local index = index_mod.get()
  if not index then
    index = M.build_project_index({ root = vim.fn.getcwd() })
  end
  if not index then
    vim.notify("code-atlas: project index is unavailable", vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local root_symbol = index_mod.find_symbol_at(index, path, row, col)
  if not root_symbol then
    vim.notify("code-atlas: no indexed function under cursor", vim.log.levels.WARN)
    return
  end

  local report, err = analysis.impact_for_symbol(index, root_symbol.id, {
    max_depth = (config.depth_limit or 2) + 4,
    include_tests = true,
  })
  if not report then
    vim.notify("code-atlas: impact analysis failed: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  local doc = render.impact_document(report)
  window.open(doc.lines, {
    title = " code-atlas impact analysis ",
    source_win = source_win,
    source_buf = bufnr,
    line_actions = doc.line_actions,
  })
end

local function parse_hot_path_args(raw_args)
  local function parse_hot_bool(value)
    local text = tostring(value):lower()
    if text == "1" or text == "true" or text == "yes" or text == "on" then
      return true
    end
    if text == "0" or text == "false" or text == "no" or text == "off" then
      return false
    end
    return nil
  end

  local out = {
    top_n = nil,
    max_depth = nil,
    path_depth = nil,
    path_count = nil,
    include_tests = nil,
    include_churn = nil,
    churn_limit = nil,
    churn_since = nil,
    churn_weight = nil,
    direction = nil,
  }

  for _, token in ipairs(raw_args or {}) do
    local key, value = token:match("^([%w_]+)=(.+)$")
    if key then
      key = key:lower()
      if key == "top" or key == "top_n" then
        local n = tonumber(value)
        if not n or n < 1 then
          return nil, "top_n must be a positive number"
        end
        out.top_n = math.floor(n)
      elseif key == "max_depth" then
        local n = tonumber(value)
        if not n or n < 1 then
          return nil, "max_depth must be a positive number"
        end
        out.max_depth = math.floor(n)
      elseif key == "path_depth" then
        local n = tonumber(value)
        if not n or n < 1 then
          return nil, "path_depth must be a positive number"
        end
        out.path_depth = math.floor(n)
      elseif key == "path_count" then
        local n = tonumber(value)
        if not n or n < 1 then
          return nil, "path_count must be a positive number"
        end
        out.path_count = math.floor(n)
      elseif key == "include_tests" then
        local parsed = parse_hot_bool(value)
        if parsed == nil then
          return nil, "include_tests must be true/false"
        end
        out.include_tests = parsed
      elseif key == "include_churn" then
        local parsed = parse_hot_bool(value)
        if parsed == nil then
          return nil, "include_churn must be true/false"
        end
        out.include_churn = parsed
      elseif key == "churn_limit" then
        local n = tonumber(value)
        if not n or n < 1 then
          return nil, "churn_limit must be a positive number"
        end
        out.churn_limit = math.floor(n)
      elseif key == "churn_since" then
        out.churn_since = value
      elseif key == "churn_weight" then
        local n = tonumber(value)
        if not n or n < 0 then
          return nil, "churn_weight must be a non-negative number"
        end
        out.churn_weight = n
      elseif key == "direction" then
        value = tostring(value):lower()
        if value ~= "incoming" and value ~= "outgoing" then
          return nil, "direction must be incoming or outgoing"
        end
        out.direction = value
      else
        return nil, "unknown option: " .. tostring(key)
      end
    elseif token == "incoming" or token == "outgoing" then
      out.direction = token
    else
      return nil, "unexpected argument: " .. tostring(token)
    end
  end

  return out, nil
end

function M.run_hot_path_detection(opts)
  opts = opts or {}
  local index_mod = require("code-atlas.index")
  local analysis = require("code-atlas.analysis")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")
  local config = require("code-atlas.config").get()

  opts = vim.tbl_deep_extend("force", vim.deepcopy(config.hot_path or {}), opts)

  local index = index_mod.get()
  if not index then
    index = M.build_project_index({ root = vim.fn.getcwd() })
  end

  if not index then
    vim.notify("code-atlas: project index is unavailable", vim.log.levels.ERROR)
    return nil, "project index unavailable"
  end

  local report, err = analysis.hot_path_report(index, opts)
  if not report then
    vim.notify("code-atlas: hot path detection failed: " .. tostring(err), vim.log.levels.ERROR)
    return nil, err
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local doc = render.hot_path_document(report)

  window.open(doc.lines, {
    title = " code-atlas hot path ",
    source_win = source_win,
    source_buf = bufnr,
    line_actions = doc.line_actions,
  })

  return report, nil
end

local function parse_export_args(raw_args)
  local out = {
    format = nil,
    path = nil,
    direction = "outgoing",
    depth = nil,
    layout = nil,
  }

  for _, token in ipairs(raw_args or {}) do
    local key, value = token:match("^([%w_]+)=(.+)$")
    if key then
      key = key:lower()
      if key == "format" then
        out.format = value
      elseif key == "path" then
        out.path = value
      elseif key == "direction" then
        out.direction = value
      elseif key == "depth" then
        out.depth = tonumber(value)
      elseif key == "layout" then
        out.layout = value
      else
        return nil, "unknown option: " .. key
      end
    elseif token == "incoming" or token == "outgoing" then
      out.direction = token
    elseif token == "hierarchical" or token == "force" then
      out.layout = token
    elseif not out.format then
      out.format = token
    elseif not out.path then
      out.path = token
    else
      return nil, "unexpected argument: " .. token
    end
  end

  if out.direction ~= "incoming" and out.direction ~= "outgoing" then
    return nil, "direction must be incoming or outgoing"
  end

  return out, nil
end

local function default_export_path(root_symbol, format)
  local export = require("code-atlas.export")
  local ext = export.default_extension(format)
  local stem = (root_symbol.name or "graph"):gsub("[^%w_%-]", "_")
  if stem == "" then
    stem = "graph"
  end
  return vim.fs.joinpath(vim.fn.getcwd(), string.format("code-atlas-%s.%s", stem, ext))
end

function M.run_graph_export(raw_args)
  local export = require("code-atlas.export")
  local index_mod = require("code-atlas.index")
  local graph = require("code-atlas.graph")
  local render = require("code-atlas.render")
  local config = require("code-atlas.config").get()

  local args, args_err = parse_export_args(raw_args)
  if not args then
    vim.notify("code-atlas: export failed: " .. tostring(args_err), vim.log.levels.ERROR)
    return nil, args_err
  end

  local format = export.normalize_format(args.format or "json")
  if not format then
    vim.notify("code-atlas: export failed: unsupported format", vim.log.levels.ERROR)
    return nil, "unsupported format"
  end

  local index = index_mod.get()
  if not index then
    index = M.build_project_index({ root = vim.fn.getcwd() })
  end
  if not index then
    vim.notify("code-atlas: project index is unavailable", vim.log.levels.ERROR)
    return nil, "project index unavailable"
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local candidates = {
    path,
    vim.fs.normalize(vim.fn.fnamemodify(path, ":p")),
    vim.fs.normalize(vim.fn.resolve(path)),
  }
  local seen = {}
  local root_symbol = nil
  local symbols_in_file = nil
  for _, candidate in ipairs(candidates) do
    if candidate and candidate ~= "" and not seen[candidate] then
      seen[candidate] = true
      symbols_in_file = index.by_path[candidate] or symbols_in_file
      root_symbol = index_mod.find_symbol_at(index, candidate, row, col)
      if root_symbol then
        break
      end
    end
  end

  if not root_symbol then
    if not symbols_in_file or #symbols_in_file == 0 then
      vim.notify(
        "code-atlas: current file has no indexed symbols (check parser/query support for this language)",
        vim.log.levels.WARN
      )
    else
      vim.notify("code-atlas: no indexed function under cursor", vim.log.levels.WARN)
    end
    return nil, "no indexed function under cursor"
  end

  local depth = args.depth
  if depth == nil then
    depth = config.depth_limit
  end

  local layout_algorithm = args.layout
  if not layout_algorithm then
    layout_algorithm = ((config.layout or {}).algorithm) or "hierarchical"
  end

  local subgraph = graph.project_subgraph(index, root_symbol.id, {
    depth_limit = depth,
    direction = args.direction,
  })
  subgraph.layout = render.layout_metadata(subgraph, {
    algorithm = layout_algorithm,
    spacing_x = (config.layout or {}).spacing_x,
    spacing_y = (config.layout or {}).spacing_y,
    iterations = (config.layout or {}).force_iterations,
  })

  local export_path = args.path
  if not export_path or export_path == "" then
    export_path = default_export_path(root_symbol, format)
  end

  local result, export_err = export.export_subgraph(index, subgraph, {
    format = format,
    path = vim.fs.normalize(export_path),
    layout_algorithm = layout_algorithm,
  })

  if not result then
    vim.notify("code-atlas: export failed: " .. tostring(export_err), vim.log.levels.ERROR)
    return nil, export_err
  end

  vim.notify(
    string.format(
      "code-atlas: exported %d nodes/%d edges to %s (%s)",
      result.node_count,
      result.edge_count,
      result.path,
      result.format
    ),
    vim.log.levels.INFO
  )

  return result, nil
end

function M.run_knowledge_graph(opts)
  opts = opts or {}
  local index_mod = require("code-atlas.index")
  local knowledge = require("code-atlas.knowledge")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")

  local index = index_mod.get()
  if not index then
    index = M.build_project_index({ root = vim.fn.getcwd() })
  end
  if not index then
    vim.notify("code-atlas: project index is unavailable", vim.log.levels.ERROR)
    return nil, "project index unavailable"
  end

  local build_opts = {
    include_tests = opts.include_tests,
    include_imports = opts.include_imports,
    include_external = opts.include_external,
    include_types = opts.include_types,
  }

  local graph, graph_err = knowledge.build(index, build_opts)
  if not graph then
    vim.notify("code-atlas: knowledge graph failed: " .. tostring(graph_err), vim.log.levels.ERROR)
    return nil, graph_err
  end

  local snapshot_path = opts.snapshot_path
  if snapshot_path and snapshot_path ~= "" then
    local write_result, write_err = knowledge.write_snapshot(vim.fs.normalize(snapshot_path), graph, {
      format = opts.snapshot_format,
      pretty = opts.snapshot_pretty,
    })
    if not write_result then
      vim.notify("code-atlas: knowledge snapshot failed: " .. tostring(write_err), vim.log.levels.ERROR)
      return nil, write_err
    end
    vim.notify(
      string.format("code-atlas: knowledge snapshot written to %s (%s)", write_result.path, write_result.format or "json"),
      vim.log.levels.INFO
    )
  end

  local doc = render.knowledge_graph_document(graph)
  window.open(doc.lines, {
    title = " code-atlas knowledge graph ",
    source_win = vim.api.nvim_get_current_win(),
    source_buf = vim.api.nvim_get_current_buf(),
    line_actions = doc.line_actions,
  })

  return graph, nil
end

local function parse_bool(value)
  if value == nil then
    return nil
  end
  local text = tostring(value):lower()
  if text == "1" or text == "true" or text == "yes" or text == "on" then
    return true
  end
  if text == "0" or text == "false" or text == "no" or text == "off" then
    return false
  end
  return nil
end

local function parse_architecture_args(raw_args)
  local out = {
    include_tests = nil,
    unknown_layer_policy = nil,
    max_violation_examples = nil,
    snapshot_path = nil,
    snapshot_format = nil,
    snapshot_pretty = nil,
  }

  for _, token in ipairs(raw_args or {}) do
    local key, value = token:match("^([%w_]+)=(.+)$")
    if key then
      key = key:lower()

      if key == "include_tests" then
        local parsed = parse_bool(value)
        if parsed == nil then
          return nil, "include_tests must be true/false"
        end
        out.include_tests = parsed
      elseif key == "unknown_policy" then
        value = tostring(value):lower()
        if value ~= "allow" and value ~= "deny" then
          return nil, "unknown_policy must be allow or deny"
        end
        out.unknown_layer_policy = value
      elseif key == "max_examples" then
        local n = tonumber(value)
        if not n or n < 1 then
          return nil, "max_examples must be a positive number"
        end
        out.max_violation_examples = math.floor(n)
      elseif key == "path" then
        out.snapshot_path = value
      elseif key == "format" then
        local format = tostring(value):lower()
        if format ~= "json" then
          return nil, "format must be json"
        end
        out.snapshot_format = format
      elseif key == "pretty" then
        local parsed = parse_bool(value)
        if parsed == nil then
          return nil, "pretty must be true/false"
        end
        out.snapshot_pretty = parsed
      else
        return nil, "unknown option: " .. tostring(key)
      end
    else
      if not out.snapshot_path then
        out.snapshot_path = token
      else
        return nil, "unexpected argument: " .. tostring(token)
      end
    end
  end

  return out, nil
end

function M.run_architecture_graph(opts)
  opts = opts or {}
  local index_mod = require("code-atlas.index")
  local analysis = require("code-atlas.analysis")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")
  local config = require("code-atlas.config").get()

  opts = vim.tbl_deep_extend("force", vim.deepcopy(config.architecture or {}), opts)

  local index = index_mod.get()
  if not index then
    index = M.build_project_index({ root = vim.fn.getcwd() })
  end
  if not index then
    vim.notify("code-atlas: project index is unavailable", vim.log.levels.ERROR)
    return nil, "project index unavailable"
  end

  local report, err = analysis.architecture_report(index, opts)
  if not report then
    vim.notify("code-atlas: architecture analysis failed: " .. tostring(err), vim.log.levels.ERROR)
    return nil, err
  end

  local snapshot_path = opts.snapshot_path
  if snapshot_path and snapshot_path ~= "" then
    local write_result, write_err = analysis.write_architecture_report(vim.fs.normalize(snapshot_path), report, {
      format = opts.snapshot_format or opts.export_format,
      pretty = opts.snapshot_pretty ~= nil and opts.snapshot_pretty or opts.export_pretty,
    })
    if not write_result then
      vim.notify("code-atlas: architecture snapshot failed: " .. tostring(write_err), vim.log.levels.ERROR)
      return nil, write_err
    end
    vim.notify(
      string.format("code-atlas: architecture snapshot written to %s (%s)", write_result.path, write_result.format),
      vim.log.levels.INFO
    )
  end

  local doc = render.architecture_graph_document(report)
  window.open(doc.lines, {
    title = " code-atlas architecture graph ",
    source_win = vim.api.nvim_get_current_win(),
    source_buf = vim.api.nvim_get_current_buf(),
    line_actions = doc.line_actions,
  })

  return report, nil
end

local function parse_evolution_args(raw_args)
  local out = {
    limit = nil,
    hotspot_limit = nil,
    include_merges = nil,
    since = nil,
    path = nil,
    timeout_ms = nil,
    snapshot_path = nil,
    snapshot_format = nil,
    snapshot_pretty = nil,
  }

  for _, token in ipairs(raw_args or {}) do
    local key, value = token:match("^([%w_]+)=(.+)$")
    if not key then
      return nil, "unexpected argument: " .. tostring(token)
    end
    key = key:lower()

    if key == "limit" then
      local n = tonumber(value)
      if not n or n < 1 then
        return nil, "limit must be a positive number"
      end
      out.limit = math.floor(n)
    elseif key == "hotspot_limit" then
      local n = tonumber(value)
      if not n or n < 1 then
        return nil, "hotspot_limit must be a positive number"
      end
      out.hotspot_limit = math.floor(n)
    elseif key == "include_merges" then
      local parsed = parse_bool(value)
      if parsed == nil then
        return nil, "include_merges must be true/false"
      end
      out.include_merges = parsed
    elseif key == "since" then
      out.since = value
    elseif key == "path" or key == "history_path" then
      out.path = value
    elseif key == "out" or key == "output" or key == "snapshot" then
      out.snapshot_path = value
    elseif key == "format" then
      local format = tostring(value):lower()
      if format ~= "json" and format ~= "jsonl" then
        return nil, "format must be json or jsonl"
      end
      out.snapshot_format = format
    elseif key == "pretty" then
      local parsed = parse_bool(value)
      if parsed == nil then
        return nil, "pretty must be true/false"
      end
      out.snapshot_pretty = parsed
    elseif key == "timeout_ms" then
      local n = tonumber(value)
      if not n or n < 1 then
        return nil, "timeout_ms must be a positive number"
      end
      out.timeout_ms = math.floor(n)
    else
      return nil, "unknown option: " .. tostring(key)
    end
  end

  return out, nil
end

function M.run_code_evolution(opts)
  opts = opts or {}
  local index_mod = require("code-atlas.index")
  local analysis = require("code-atlas.analysis")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")
  local config = require("code-atlas.config").get()

  opts = vim.tbl_deep_extend("force", vim.deepcopy(config.evolution or {}), opts)

  local index = index_mod.get()
  if not index then
    index = M.build_project_index({ root = vim.fn.getcwd() })
  end
  if not index then
    vim.notify("code-atlas: project index is unavailable", vim.log.levels.ERROR)
    return nil, "project index unavailable"
  end

  local report, err = analysis.code_evolution_report(index, opts)
  if not report then
    vim.notify("code-atlas: evolution analysis failed: " .. tostring(err), vim.log.levels.ERROR)
    return nil, err
  end

  local snapshot_path = opts.snapshot_path
  if snapshot_path and snapshot_path ~= "" then
    local write_result, write_err = analysis.write_evolution_report(vim.fs.normalize(snapshot_path), report, {
      format = opts.snapshot_format or opts.export_format,
      pretty = opts.snapshot_pretty ~= nil and opts.snapshot_pretty or opts.export_pretty,
    })
    if not write_result then
      vim.notify("code-atlas: evolution snapshot failed: " .. tostring(write_err), vim.log.levels.ERROR)
      return nil, write_err
    end
    vim.notify(
      string.format("code-atlas: evolution snapshot written to %s (%s)", write_result.path, write_result.format),
      vim.log.levels.INFO
    )
  end

  local doc = render.code_evolution_document(report)
  window.open(doc.lines, {
    title = " code-atlas evolution graph ",
    source_win = vim.api.nvim_get_current_win(),
    source_buf = vim.api.nvim_get_current_buf(),
    line_actions = doc.line_actions,
  })

  return report, nil
end

local function parse_viewer_args(raw_args)
  local out = {
    direction = nil,
    depth_limit = nil,
    dynamic_only = nil,
    filter_path_prefix = nil,
    search_query = nil,
    node_kind = nil,
  }

  for _, token in ipairs(raw_args or {}) do
    local key, value = token:match("^([%w_]+)=(.+)$")
    if key then
      key = key:lower()
      if key == "direction" then
        value = tostring(value):lower()
        if value ~= "incoming" and value ~= "outgoing" then
          return nil, "direction must be incoming or outgoing"
        end
        out.direction = value
      elseif key == "depth" or key == "depth_limit" then
        local n = tonumber(value)
        if not n or n < 0 then
          return nil, "depth must be a non-negative number"
        end
        out.depth_limit = math.floor(n)
      elseif key == "dynamic" or key == "dynamic_only" then
        local parsed = parse_bool(value)
        if parsed == nil then
          return nil, "dynamic_only must be true/false"
        end
        out.dynamic_only = parsed
      elseif key == "filter" or key == "filter_path" then
        out.filter_path_prefix = value
      elseif key == "search" or key == "query" then
        out.search_query = value
      elseif key == "kind" or key == "node_kind" then
        local kind = tostring(value):lower()
        if kind ~= "all" and kind ~= "function" and kind ~= "method" then
          return nil, "node_kind must be all, function, or method"
        end
        out.node_kind = kind
      else
        return nil, "unknown option: " .. tostring(key)
      end
    elseif token == "incoming" or token == "outgoing" then
      out.direction = token
    else
      return nil, "unexpected argument: " .. tostring(token)
    end
  end

  return out, nil
end

function M.run_interactive_viewer(opts)
  opts = opts or {}
  local index_mod = require("code-atlas.index")
  local render = require("code-atlas.render")
  local window = require("code-atlas.window")
  local viewer = require("code-atlas.viewer")
  local config = require("code-atlas.config").get()

  opts = vim.tbl_deep_extend("force", vim.deepcopy(config.viewer or {}), opts)

  local index = index_mod.get()
  if not index then
    index = M.build_project_index({ root = vim.fn.getcwd() })
  end
  if not index then
    vim.notify("code-atlas: project index is unavailable", vim.log.levels.ERROR)
    return nil, "project index unavailable"
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  local root_symbol = index_mod.find_symbol_at(index, path, row, col)
  if not root_symbol then
    vim.notify("code-atlas: no indexed function under cursor", vim.log.levels.WARN)
    return nil, "no indexed function under cursor"
  end

  local session = viewer.new_session(index, {
    root_id = root_symbol.id,
    depth_limit = opts.depth_limit,
    direction = opts.direction,
    node_kind_filter = opts.node_kind,
  })
  viewer.set_filter_path(session, opts.filter_path_prefix)
  viewer.set_search(session, opts.search_query)
  if opts.dynamic_only == true then
    session.dynamic_only = true
  end

  local function selected_symbol_id()
    local state = window.get_state()
    if not state.win or not vim.api.nvim_win_is_valid(state.win) then
      return nil
    end
    local line = vim.api.nvim_win_get_cursor(state.win)[1]
    local action = (state.line_actions or {})[line]
    return action and action.symbol_id or nil
  end

  local function redraw()
    local subgraph, stats = viewer.build_subgraph(session)
    local doc = render.interactive_viewer_document(index, subgraph, {
      focus_root = session.focus_root_id,
      depth_limit = session.depth_limit,
      filter_path_prefix = session.filter_path_prefix,
      search_query = session.search_query,
      dynamic_only = session.dynamic_only,
      node_kind = session.node_kind_filter,
      focus_history_size = #session.focus_history,
      hidden_nodes = stats.hidden_nodes,
      total_nodes = stats.total_nodes,
    })

    viewer.update_search_matches(session, doc.lines)

    window.open(doc.lines, {
      title = " code-atlas interactive viewer ",
      source_win = source_win,
      source_buf = bufnr,
      line_actions = doc.line_actions,
      on_refresh = redraw,
      line_highlights = (function()
        local highlights = {}
        for _, line in ipairs(session.search_matches or {}) do
          highlights[#highlights + 1] = { line = line, group = "Search" }
        end
        return highlights
      end)(),
      key_actions = {
        ["f"] = function()
          local symbol_id = selected_symbol_id()
          if not symbol_id then
            vim.notify("code-atlas: select a symbol line to focus", vim.log.levels.WARN)
            return
          end
          viewer.push_focus(session, symbol_id)
          redraw()
        end,
        ["F"] = function()
          session.focus_root_id = session.initial_root_id
          session.focus_history = { session.initial_root_id }
          session.focus_history_index = 1
          redraw()
        end,
        ["/"] = function()
          vim.ui.input({
            prompt = "code-atlas viewer search: ",
            default = session.search_query or "",
          }, function(input)
            if input ~= nil then
              viewer.set_search(session, input)
              redraw()
            end
          end)
        end,
        ["n"] = function()
          if not viewer.jump_to_search_match(session, 1) then
            vim.notify("code-atlas: no search matches", vim.log.levels.WARN)
          end
        end,
        ["N"] = function()
          if not viewer.jump_to_search_match(session, -1) then
            vim.notify("code-atlas: no search matches", vim.log.levels.WARN)
          end
        end,
        ["s"] = function()
          vim.ui.input({
            prompt = "code-atlas viewer path filter: ",
            default = session.filter_path_prefix or "",
          }, function(input)
            if input ~= nil then
              viewer.set_filter_path(session, input)
              redraw()
            end
          end)
        end,
        ["k"] = function()
          vim.ui.select({ "all", "function", "method" }, {
            prompt = "code-atlas viewer node kind:",
            format_item = function(item)
              return item
            end,
          }, function(choice)
            if choice then
              viewer.set_node_kind_filter(session, choice)
              redraw()
            end
          end)
        end,
        ["d"] = function()
          viewer.toggle_dynamic_only(session)
          redraw()
        end,
        ["+"] = function()
          viewer.adjust_depth(session, 1)
          redraw()
        end,
        ["-"] = function()
          viewer.adjust_depth(session, -1)
          redraw()
        end,
        ["H"] = function()
          if viewer.pan_graph(session, "in") then
            redraw()
          else
            vim.notify("code-atlas: no incoming neighbor for pan", vim.log.levels.WARN)
          end
        end,
        ["L"] = function()
          if viewer.pan_graph(session, "out") then
            redraw()
          else
            vim.notify("code-atlas: no outgoing neighbor for pan", vim.log.levels.WARN)
          end
        end,
        ["B"] = function()
          if viewer.pan_history(session, -1) then
            redraw()
          else
            vim.notify("code-atlas: no previous focus history", vim.log.levels.WARN)
          end
        end,
        ["W"] = function()
          if viewer.pan_history(session, 1) then
            redraw()
          else
            vim.notify("code-atlas: no forward focus history", vim.log.levels.WARN)
          end
        end,
      },
    })

    if #session.search_matches > 0 then
      local state = window.get_state()
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        local line = session.search_matches[session.search_match_idx]
        vim.api.nvim_win_set_cursor(state.win, { line, 0 })
      end
    end
  end

  redraw()
  return session, nil
end

function M.set_ui_mode(mode)
  mode = (mode or ""):lower()
  if mode ~= "tree" and mode ~= "ascii" then
    vim.notify("code-atlas: ui mode must be 'tree' or 'ascii'", vim.log.levels.WARN)
    return false
  end

  local config = require("code-atlas.config").get()
  config.ui = config.ui or {}
  config.ui.mode = mode
  vim.notify("code-atlas: ui mode set to " .. mode, vim.log.levels.INFO)
  return true
end

function M.create_user_commands()
  if vim.g.code_atlas_commands_created then
    return
  end

  vim.api.nvim_create_user_command("CodeAtlas", function()
    M.run()
  end, {
    desc = "Open code-atlas call graph",
  })

  vim.api.nvim_create_user_command("CodeAtlasPick", function()
    M.pick_with_telescope()
  end, {
    desc = "Pick a function with Telescope and open code-atlas graph",
  })

  vim.api.nvim_create_user_command("CodeAtlasIndex", function()
    M.build_project_index({ root = vim.fn.getcwd() })
  end, {
    desc = "Build project-wide function index",
  })

  vim.api.nvim_create_user_command("CodeAtlasIndexRefresh", function()
    M.refresh_project_index()
  end, {
    desc = "Refresh project-wide function index",
  })

  vim.api.nvim_create_user_command("CodeAtlasProjectGraph", function()
    M.run_project_call_graph()
  end, {
    desc = "Open project-wide call graph from indexed symbols",
  })

  vim.api.nvim_create_user_command("CodeAtlasProjectReverseGraph", function()
    M.run_project_reverse_call_graph()
  end, {
    desc = "Open reverse project-wide call graph from indexed symbols",
  })

  vim.api.nvim_create_user_command("CodeAtlasLSPGraph", function()
    M.run_lsp_call_graph("outgoing")
  end, {
    desc = "Open LSP call hierarchy graph (callees)",
  })

  vim.api.nvim_create_user_command("CodeAtlasLSPReverseGraph", function()
    M.run_lsp_call_graph("incoming")
  end, {
    desc = "Open LSP reverse call hierarchy graph (callers)",
  })

  vim.api.nvim_create_user_command("CodeAtlasLSPDebug", function()
    M.show_lsp_debug()
  end, {
    desc = "Show LSP call hierarchy debug report",
  })

  vim.api.nvim_create_user_command("CodeAtlasModuleGraph", function()
    M.run_module_dependency_graph("module")
  end, {
    desc = "Open module dependency graph from indexed symbols",
  })

  vim.api.nvim_create_user_command("CodeAtlasPackageGraph", function()
    M.run_module_dependency_graph("package")
  end, {
    desc = "Open package dependency graph from indexed symbols",
  })

  vim.api.nvim_create_user_command("CodeAtlasImportGraph", function()
    M.run_import_graph("outgoing")
  end, {
    desc = "Open import graph rooted at current file",
  })

  vim.api.nvim_create_user_command("CodeAtlasImportReverseGraph", function()
    M.run_import_graph("incoming")
  end, {
    desc = "Open reverse import graph (dependents) rooted at current file",
  })

  vim.api.nvim_create_user_command("CodeAtlasDeadCode", function()
    M.run_dead_code_detection()
  end, {
    desc = "Detect dead functions (zero incoming calls)",
  })

  vim.api.nvim_create_user_command("CodeAtlasImpact", function()
    M.run_impact_analysis()
  end, {
    desc = "Analyze impact if current function changes or is removed",
  })

  vim.api.nvim_create_user_command("CodeAtlasHotPath", function(args)
    local parsed, parse_err = parse_hot_path_args(args.fargs)
    if not parsed then
      vim.notify("code-atlas: hot path args invalid: " .. tostring(parse_err), vim.log.levels.ERROR)
      return
    end
    M.run_hot_path_detection(parsed)
  end, {
    nargs = "*",
    complete = function()
      return {
        "outgoing",
        "incoming",
        "top=10",
        "max_depth=4",
        "path_depth=5",
        "path_count=5",
        "include_tests=false",
        "include_tests=true",
        "include_churn=true",
        "include_churn=false",
        "churn_limit=60",
        "churn_since=30 days ago",
        "churn_weight=0.15",
      }
    end,
    desc = "Rank critical functions and call paths using graph centrality heuristics",
  })

  vim.api.nvim_create_user_command("CodeAtlasExport", function(args)
    M.run_graph_export(args.fargs)
  end, {
    nargs = "*",
    complete = function(_, cmdline)
      local has_format = cmdline:find("%f[%w]json%f[%W]")
        or cmdline:find("%f[%w]mermaid%f[%W]")
        or cmdline:find("%f[%w]graphviz%f[%W]")
        or cmdline:find("%f[%w]dot%f[%W]")
      if not has_format then
        return { "json", "graphviz", "mermaid", "incoming", "outgoing", "hierarchical", "force" }
      end
      return { "path=", "direction=outgoing", "direction=incoming", "depth=", "layout=hierarchical", "layout=force" }
    end,
    desc = "Export project graph (json|graphviz|mermaid)",
  })

  vim.api.nvim_create_user_command("CodeAtlasKnowledge", function(args)
    local parsed = {
      snapshot_path = nil,
      snapshot_format = nil,
      snapshot_pretty = nil,
      include_tests = nil,
      include_imports = nil,
      include_external = nil,
      include_types = nil,
    }
    for _, token in ipairs(args.fargs or {}) do
      local key, value = token:match("^([%w_]+)=(.+)$")
      if key then
        key = key:lower()
        if key == "path" then
          parsed.snapshot_path = value
        elseif key == "format" then
          parsed.snapshot_format = value
        elseif key == "pretty" then
          parsed.snapshot_pretty = value
        elseif key == "include_tests" then
          parsed.include_tests = value
        elseif key == "include_imports" then
          parsed.include_imports = value
        elseif key == "include_external" then
          parsed.include_external = value
        elseif key == "include_types" then
          parsed.include_types = value
        end
      elseif not parsed.snapshot_path then
        parsed.snapshot_path = token
      end
    end
    M.run_knowledge_graph(parsed)
  end, {
    nargs = "*",
    complete = function()
      return {
        "path=",
        "format=json",
        "format=jsonl",
        "pretty=true",
        "include_tests=true",
        "include_tests=false",
        "include_imports=true",
        "include_imports=false",
        "include_external=true",
        "include_external=false",
        "include_types=true",
        "include_types=false",
      }
    end,
    desc = "Build knowledge graph summary and optional snapshot",
  })

  vim.api.nvim_create_user_command("CodeAtlasArchitecture", function(args)
    local parsed, parse_err = parse_architecture_args(args.fargs)
    if not parsed then
      vim.notify("code-atlas: architecture args invalid: " .. tostring(parse_err), vim.log.levels.ERROR)
      return
    end
    M.run_architecture_graph(parsed)
  end, {
    nargs = "*",
    complete = function()
      return {
        "include_tests=true",
        "include_tests=false",
        "unknown_policy=allow",
        "unknown_policy=deny",
        "max_examples=3",
        "path=",
        "format=json",
        "pretty=true",
        "pretty=false",
      }
    end,
    desc = "Show architecture layer dependency report and violations",
  })

  vim.api.nvim_create_user_command("CodeAtlasEvolution", function(args)
    local parsed, parse_err = parse_evolution_args(args.fargs)
    if not parsed then
      vim.notify("code-atlas: evolution args invalid: " .. tostring(parse_err), vim.log.levels.ERROR)
      return
    end
    M.run_code_evolution(parsed)
  end, {
    nargs = "*",
    complete = function()
      return {
        "limit=30",
        "hotspot_limit=10",
        "include_merges=false",
        "include_merges=true",
        "since=30 days ago",
        "path=lua/code-atlas",
        "out=",
        "format=json",
        "format=jsonl",
        "pretty=true",
        "pretty=false",
        "timeout_ms=5000",
      }
    end,
    desc = "Show code evolution timeline and churn hotspots from git history",
  })

  vim.api.nvim_create_user_command("CodeAtlasViewer", function(args)
    local parsed, parse_err = parse_viewer_args(args.fargs)
    if not parsed then
      vim.notify("code-atlas: viewer args invalid: " .. tostring(parse_err), vim.log.levels.ERROR)
      return
    end
    M.run_interactive_viewer(parsed)
  end, {
    nargs = "*",
    complete = function()
      return {
        "outgoing",
        "incoming",
        "direction=outgoing",
        "direction=incoming",
        "depth=3",
        "dynamic_only=true",
        "dynamic_only=false",
        "kind=all",
        "kind=function",
        "kind=method",
        "filter=lua/code-atlas",
        "search=graph",
      }
    end,
    desc = "Open advanced interactive graph viewer with focus/filter/search",
  })

  vim.api.nvim_create_user_command("CodeAtlasUI", function(args)
    M.set_ui_mode(args.args)
  end, {
    nargs = 1,
    complete = function()
      return { "tree", "ascii" }
    end,
    desc = "Set code-atlas UI mode (tree|ascii)",
  })

  vim.g.code_atlas_commands_created = true
end

function M.setup(opts)
  require("code-atlas.config").setup(opts)
  M.create_user_commands()
  M._is_setup = true
  return M
end

return M
