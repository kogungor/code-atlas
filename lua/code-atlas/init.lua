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
  local index, err = require("code-atlas.index").refresh()
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

  local subgraph = graph.project_subgraph(index, root_symbol.id, {
    depth_limit = config.depth_limit,
    direction = direction,
  })
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

  local root_symbol = index_mod.find_symbol_at(index, path, row, col)
  if not root_symbol then
    vim.notify("code-atlas: no indexed function under cursor", vim.log.levels.WARN)
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
