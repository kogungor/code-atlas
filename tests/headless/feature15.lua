local root = vim.fn.getcwd()

if vim.fn.exists(":CodeAtlasDeadCode") ~= 2 then
  error("feature15 smoke failed: :CodeAtlasDeadCode command is not registered")
end

local atlas = require("code-atlas")
local index = atlas.build_project_index({ root = root })
if not index then
  error("feature15 smoke failed: project index build failed")
end

local analysis = require("code-atlas.analysis")
local report, err = analysis.detect_dead_code(index, {
  ignore_tests = false,
  ignore_entrypoints = false,
  ignore_path_prefixes = {},
})
if not report then
  error("feature15 smoke failed: " .. tostring(err))
end

local found_orphan = false
for _, symbol in ipairs(report.dead) do
  if symbol.name == "orphan" and (symbol.relpath or ""):find("dead_code_case.lua", 1, true) then
    found_orphan = true
    break
  end
end

if not found_orphan then
  error("feature15 smoke failed: expected dead function 'orphan' from dead_code_case.lua")
end

atlas.run_dead_code_detection()
local state = require("code-atlas.window").get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature15 smoke failed: dead code report window was not created")
end

local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local text = table.concat(lines, "\n")
if not text:find("code%-atlas dead code report") then
  error("feature15 smoke failed: expected dead code report heading")
end

vim.notify("feature15 smoke passed", vim.log.levels.INFO)
