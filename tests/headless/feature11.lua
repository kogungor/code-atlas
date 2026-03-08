local sample = vim.fn.getcwd() .. "/playground/samples/checkout_flow.lua"

if vim.fn.exists(":CodeAtlasProjectReverseGraph") ~= 2 then
  error("feature11 smoke failed: :CodeAtlasProjectReverseGraph command is not registered")
end

require("code-atlas").setup({
  depth_limit = 2,
})

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local target_line = vim.fn.search("^local function normalize_coupon", "nw")
if target_line == 0 then
  error("feature11 smoke failed: could not locate function normalize_coupon")
end
vim.api.nvim_win_set_cursor(0, { target_line, 2 })

require("code-atlas").build_project_index({ root = vim.fn.getcwd() })
require("code-atlas").run_project_reverse_call_graph()

local window = require("code-atlas.window")
local state = window.get_state()

if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature11 smoke failed: reverse graph window was not created")
end

local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local text = table.concat(lines, "\n")

if not text:find("mode: callers", 1, true) then
  error("feature11 smoke failed: expected reverse mode label")
end

if not text:find("apply_discount_rules", 1, true) then
  error("feature11 smoke failed: expected caller 'apply_discount_rules' in reverse graph")
end

vim.notify("feature11 smoke passed", vim.log.levels.INFO)
