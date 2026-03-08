local sample = vim.fn.getcwd() .. "/playground/samples/checkout_flow.lua"

if vim.fn.exists(":CodeAtlasModuleGraph") ~= 2 then
  error("feature13 smoke failed: :CodeAtlasModuleGraph command is not registered")
end

require("code-atlas").setup({
  depth_limit = 3,
})

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local checkout_line = vim.fn.search("^function M\\.checkout", "nw")
if checkout_line == 0 then
  error("feature13 smoke failed: could not locate function M.checkout")
end
vim.api.nvim_win_set_cursor(0, { checkout_line, 2 })

require("code-atlas").build_project_index({ root = vim.fn.getcwd() })
require("code-atlas").run_module_dependency_graph("module")

local window = require("code-atlas.window")
local state = window.get_state()

if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature13 smoke failed: module graph window was not created")
end

local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local text = table.concat(lines, "\n")

if not text:find("code%-atlas module graph") then
  error("feature13 smoke failed: expected module graph title")
end

if not text:find("summary_nodes:", 1, true) then
  error("feature13 smoke failed: expected summary stats output")
end

if not text:find("playground.samples.checkout_flow", 1, true) then
  error("feature13 smoke failed: expected checkout module in graph")
end

if not text:find("playground.samples.lua_sample", 1, true) then
  error("feature13 smoke failed: expected cross-module dependency node")
end

vim.notify("feature13 smoke passed", vim.log.levels.INFO)
