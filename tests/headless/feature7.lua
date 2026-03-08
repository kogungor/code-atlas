local sample = vim.fn.getcwd() .. "/playground/samples/lua_sample.lua"

require("code-atlas").setup({
  depth_limit = 1,
})

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local run_line = vim.fn.search("^function M\\.run", "nw")
if run_line == 0 then
  error("feature7 smoke failed: could not locate function M.run")
end
vim.api.nvim_win_set_cursor(0, { run_line, 2 })

require("code-atlas").run()

local window = require("code-atlas.window")
local state = window.get_state()

if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature7 smoke failed: graph window was not created")
end

local function line_index(lines, needle)
  for i, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      return i
    end
  end
  return nil
end

local lines_before = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
if not line_index(lines_before, "greet") then
  error("feature7 smoke failed: expected greet node")
end

if line_index(lines_before, "format_name") then
  error("feature7 smoke failed: depth limit should hide format_name")
end

local greet_line = line_index(lines_before, "greet")
vim.api.nvim_win_set_cursor(state.win, { greet_line, 0 })
window.expand_node()

local state_after = window.get_state()
local lines_after = vim.api.nvim_buf_get_lines(state_after.buf, 0, -1, false)
if line_index(lines_after, "format_name") then
  error("feature7 smoke failed: expanding should still respect depth limit")
end

vim.notify("feature7 smoke passed", vim.log.levels.INFO)
