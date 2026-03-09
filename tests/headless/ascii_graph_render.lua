local sample = vim.fn.getcwd() .. "/playground/samples/lua_sample.lua"

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local run_line = vim.fn.search("^function M\\.run", "nw")
if run_line == 0 then
  error("feature4 smoke failed: could not locate function M.run")
end
vim.api.nvim_win_set_cursor(0, { run_line, 2 })

require("code-atlas").run()

local window = require("code-atlas.window")
local state = window.get_state()

if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature4 smoke failed: floating window was not created")
end

if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
  error("feature4 smoke failed: floating buffer was not created")
end

local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local text = table.concat(lines, "\n")

if not text:find("root:", 1, true) then
  error("feature4 smoke failed: graph root line missing")
end

if not text:find("greet", 1, true) then
  error("feature4 smoke failed: expected local call 'greet' in graph")
end

vim.notify("feature4 smoke passed", vim.log.levels.INFO)
