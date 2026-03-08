local sample = vim.fn.getcwd() .. "/playground/samples/lua_sample.lua"

if vim.fn.exists(":CodeAtlas") ~= 2 then
  error("feature2 smoke failed: :CodeAtlas command is not registered")
end

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local run_line = vim.fn.search("^function M\\.run", "nw")
if run_line == 0 then
  error("feature2 smoke failed: could not locate function M.run")
end
vim.api.nvim_win_set_cursor(0, { run_line, 2 })

local treesitter = require("code-atlas.treesitter")
local func, err = treesitter.get_current_function(0)

if not func then
  error("feature2 smoke failed: " .. tostring(err))
end

if func.name ~= "run" and func.name ~= "M.run" then
  error("feature2 smoke failed: expected function 'run' or 'M.run', got '" .. tostring(func.name) .. "'")
end

if func.lang ~= "lua" then
  error("feature2 smoke failed: expected language 'lua', got '" .. tostring(func.lang) .. "'")
end

vim.notify("feature2 smoke passed", vim.log.levels.INFO)
