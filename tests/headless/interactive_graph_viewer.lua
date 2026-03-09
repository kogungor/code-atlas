local root = vim.fn.getcwd()

if vim.fn.exists(":CodeAtlasViewer") ~= 2 then
  error("feature26 smoke failed: :CodeAtlasViewer command is not registered")
end

local atlas = require("code-atlas")
atlas.setup({
  depth_limit = 2,
  viewer = {
    depth_limit = 3,
    direction = "outgoing",
    dynamic_only = false,
    filter_path_prefix = "lua/code-atlas",
    search_query = "graph",
  },
})

local index, build_err = atlas.build_project_index({ root = root })
if not index then
  error("feature26 smoke failed: index build failed: " .. tostring(build_err))
end

vim.cmd("edit " .. vim.fn.fnameescape(root .. "/lua/code-atlas/init.lua"))
vim.api.nvim_win_set_cursor(0, { 6, 0 })

local session, viewer_err = atlas.run_interactive_viewer({
  depth_limit = 2,
  direction = "outgoing",
  search_query = "graph",
  filter_path_prefix = "lua/code-atlas",
})
if not session then
  error("feature26 smoke failed: viewer session failed: " .. tostring(viewer_err))
end

if not session.focus_root_id then
  error("feature26 smoke failed: expected focus root")
end

require("code-atlas.window").close()
vim.cmd("edit " .. vim.fn.fnameescape(root .. "/lua/code-atlas/init.lua"))
vim.api.nvim_win_set_cursor(0, { 6, 0 })

vim.cmd("CodeAtlasViewer outgoing depth=2 search=graph filter=lua/code-atlas dynamic_only=false")

local state = require("code-atlas.window").get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature26 smoke failed: viewer window was not created")
end

local text = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
if not text:find("code%-atlas interactive viewer") then
  error("feature26 smoke failed: expected interactive viewer title")
end
if not text:find("controls:", 1, true) then
  error("feature26 smoke failed: expected controls section")
end
if not text:find("filter_path:", 1, true) then
  error("feature26 smoke failed: expected filter_path metadata")
end
if not text:find("node_kind:", 1, true) then
  error("feature26 smoke failed: expected node_kind metadata")
end
if not text:find("hidden_nodes:", 1, true) then
  error("feature26 smoke failed: expected hidden_nodes metadata")
end

vim.notify("feature26 smoke passed", vim.log.levels.INFO)
