local sample = vim.fn.getcwd() .. "/playground/samples/checkout_flow.lua"

vim.cmd("edit " .. vim.fn.fnameescape(sample))

require("code-atlas").run_for_function_name("calculate_total", 0)

local window = require("code-atlas.window")
local state = window.get_state()

if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature8 smoke failed: graph window was not created")
end

local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local text = table.concat(lines, "\n")

if not text:find("root: calculate_total", 1, true) then
  error("feature8 smoke failed: expected root function 'calculate_total'")
end

if not text:find("apply_discount_rules", 1, true) then
  error("feature8 smoke failed: expected local call 'apply_discount_rules'")
end

vim.notify("feature8 smoke passed", vim.log.levels.INFO)
