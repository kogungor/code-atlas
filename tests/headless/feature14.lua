local root = vim.fn.getcwd()
local checkout = root .. "/playground/samples/checkout_flow.lua"
local sample = root .. "/playground/samples/lua_sample.lua"

if vim.fn.exists(":CodeAtlasImportGraph") ~= 2 then
  error("feature14 smoke failed: :CodeAtlasImportGraph command is not registered")
end

if vim.fn.exists(":CodeAtlasImportReverseGraph") ~= 2 then
  error("feature14 smoke failed: :CodeAtlasImportReverseGraph command is not registered")
end

local atlas = require("code-atlas")
atlas.build_project_index({ root = root })

vim.cmd("edit " .. vim.fn.fnameescape(checkout))
atlas.run_import_graph("outgoing")

local window = require("code-atlas.window")
local state = window.get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature14 smoke failed: import graph window was not created")
end

local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local text = table.concat(lines, "\n")
if not text:find("code%-atlas import graph") then
  error("feature14 smoke failed: expected import graph title")
end
if not text:find("playground/samples/checkout_flow.lua", 1, true) then
  error("feature14 smoke failed: expected checkout_flow file node")
end
if not text:find("playground/samples/lua_sample.lua", 1, true) then
  error("feature14 smoke failed: expected lua_sample import dependency")
end

vim.cmd("edit " .. vim.fn.fnameescape(sample))
atlas.run_import_graph("incoming")

local state2 = window.get_state()
local lines2 = vim.api.nvim_buf_get_lines(state2.buf, 0, -1, false)
local text2 = table.concat(lines2, "\n")
if not text2:find("reverse import graph", 1, true) then
  error("feature14 smoke failed: expected reverse import graph title")
end
if not text2:find("playground/samples/checkout_flow.lua", 1, true) then
  error("feature14 smoke failed: expected checkout_flow as dependent in reverse import graph")
end

vim.notify("feature14 smoke passed", vim.log.levels.INFO)
