local sample = vim.fn.getcwd() .. "/playground/samples/lua_sample.lua"

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local run_line = vim.fn.search("^function M\\.run", "nw")
if run_line == 0 then
  error("feature3 smoke failed: could not locate function M.run")
end
vim.api.nvim_win_set_cursor(0, { run_line, 2 })

local treesitter = require("code-atlas.treesitter")
local calls, err = treesitter.get_local_calls(0)

if not calls then
  error("feature3 smoke failed: " .. tostring(err))
end

if #calls < 1 then
  error("feature3 smoke failed: expected at least one call")
end

local found_greet = false
for _, call in ipairs(calls) do
  if call.name == "greet" then
    found_greet = true
    break
  end
end

if not found_greet then
  error("feature3 smoke failed: expected to find call to 'greet'")
end

vim.notify("feature3 smoke passed", vim.log.levels.INFO)
