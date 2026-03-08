local sample = vim.fn.getcwd() .. "/playground/samples/lua_sample.lua"

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local run_line = vim.fn.search("^function M\\.run", "nw")
if run_line == 0 then
  error("feature5 smoke failed: could not locate function M.run")
end
vim.api.nvim_win_set_cursor(0, { run_line, 2 })

require("code-atlas").run()

local window = require("code-atlas.window")
local state = window.get_state()

if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature5 smoke failed: graph window was not created")
end

local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local jump_line = nil
for i, line in ipairs(lines) do
  if line:find("greet", 1, true) then
    jump_line = i
    break
  end
end

if not jump_line then
  error("feature5 smoke failed: could not find greet node in graph")
end

vim.api.nvim_win_set_cursor(state.win, { jump_line, 0 })
window.jump_to_node()

local cursor = vim.api.nvim_win_get_cursor(0)
local current_line = vim.api.nvim_get_current_line()
if not current_line:find("local function greet", 1, true) then
  error("feature5 smoke failed: expected cursor on greet definition, got line " .. tostring(cursor[1]))
end

vim.notify("feature5 smoke passed", vim.log.levels.INFO)
