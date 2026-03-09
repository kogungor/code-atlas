local sample = vim.fn.getcwd() .. "/playground/samples/checkout_flow.lua"

if vim.fn.exists(":CodeAtlasProjectGraph") ~= 2 then
  error("feature10 smoke failed: :CodeAtlasProjectGraph command is not registered")
end

require("code-atlas").setup({
  depth_limit = 3,
})

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local checkout_line = vim.fn.search("^function M\\.checkout", "nw")
if checkout_line == 0 then
  error("feature10 smoke failed: could not locate function M.checkout")
end

vim.api.nvim_win_set_cursor(0, { checkout_line, 2 })

require("code-atlas").build_project_index({ root = vim.fn.getcwd() })
require("code-atlas").run_project_call_graph()

local window = require("code-atlas.window")
local state = window.get_state()

if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature10 smoke failed: project graph window was not created")
end

local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local text = table.concat(lines, "\n")

if not text:find("checkout_flow.lua", 1, true) then
  error("feature10 smoke failed: expected checkout_flow symbols in graph")
end

if not text:find("lua_sample.lua", 1, true) then
  error("feature10 smoke failed: expected cross-file edge target in graph")
end

vim.api.nvim_win_set_cursor(state.win, { 3, 0 })
window.jump_to_node()

local current = vim.api.nvim_get_current_line()
if not current:find("function M.checkout", 1, true) then
  error("feature10 smoke failed: root line jump did not open checkout definition")
end

vim.notify("feature10 smoke passed", vim.log.levels.INFO)
