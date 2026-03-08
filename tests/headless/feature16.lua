local root = vim.fn.getcwd()
local sample = root .. "/playground/samples/checkout_flow.lua"

if vim.fn.exists(":CodeAtlasImpact") ~= 2 then
  error("feature16 smoke failed: :CodeAtlasImpact command is not registered")
end

local atlas = require("code-atlas")
atlas.build_project_index({ root = root })

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local line = vim.fn.search("^local function normalize_coupon", "nw")
if line == 0 then
  error("feature16 smoke failed: could not locate normalize_coupon")
end
vim.api.nvim_win_set_cursor(0, { line, 2 })

atlas.run_impact_analysis()

local state = require("code-atlas.window").get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature16 smoke failed: impact analysis window was not created")
end

local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local text = table.concat(lines, "\n")

if not text:find("code%-atlas impact analysis") then
  error("feature16 smoke failed: expected impact report title")
end

if not text:find("apply_discount_rules", 1, true) then
  error("feature16 smoke failed: expected impacted caller apply_discount_rules")
end

if not text:find("calculate_total", 1, true) then
  error("feature16 smoke failed: expected transitive impacted caller calculate_total")
end

if not text:find("M.checkout", 1, true) then
  error("feature16 smoke failed: expected transitive impacted caller M.checkout")
end

vim.notify("feature16 smoke passed", vim.log.levels.INFO)
