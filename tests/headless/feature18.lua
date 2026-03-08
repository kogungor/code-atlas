local root = vim.fn.getcwd()
local sample = root .. "/playground/samples/checkout_flow.lua"

if vim.fn.exists(":CodeAtlasExport") ~= 2 then
  error("feature18 smoke failed: :CodeAtlasExport command is not registered")
end

local atlas = require("code-atlas")
atlas.setup({
  depth_limit = 2,
})
atlas.build_project_index({ root = root })

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local checkout_line = vim.fn.search("^function M\\.checkout", "nw")
if checkout_line == 0 then
  error("feature18 smoke failed: could not locate M.checkout")
end
vim.api.nvim_win_set_cursor(0, { checkout_line, 2 })

local json_path = vim.fn.tempname() .. ".json"
local dot_path = vim.fn.tempname() .. ".dot"
local mmd_path = vim.fn.tempname() .. ".mmd"

local json_result, json_err = atlas.run_graph_export({ "json", json_path })
if not json_result then
  error("feature18 smoke failed: json export error: " .. tostring(json_err))
end

local json_lines = vim.fn.readfile(json_path)
local json_text = table.concat(json_lines, "\n")
if not json_text:find('"nodes"', 1, true) then
  error("feature18 smoke failed: json export missing nodes")
end
if not json_text:find('"edges"', 1, true) then
  error("feature18 smoke failed: json export missing edges")
end

local dot_result, dot_err = atlas.run_graph_export({ "graphviz", dot_path, "depth=1" })
if not dot_result then
  error("feature18 smoke failed: graphviz export error: " .. tostring(dot_err))
end

local dot_lines = vim.fn.readfile(dot_path)
local dot_text = table.concat(dot_lines, "\n")
if not dot_text:find("digraph CodeAtlas", 1, true) then
  error("feature18 smoke failed: graphviz export missing digraph header")
end
if not dot_text:find("->", 1, true) then
  error("feature18 smoke failed: graphviz export missing edge")
end

local mmd_result, mmd_err = atlas.run_graph_export({ "mermaid", mmd_path, "incoming" })
if not mmd_result then
  error("feature18 smoke failed: mermaid export error: " .. tostring(mmd_err))
end

local mmd_lines = vim.fn.readfile(mmd_path)
local mmd_text = table.concat(mmd_lines, "\n")
if not mmd_text:find("flowchart LR", 1, true) then
  error("feature18 smoke failed: mermaid export missing flowchart header")
end
if not mmd_text:find("[\"", 1, true) then
  error("feature18 smoke failed: mermaid export missing node entries")
end

vim.notify("feature18 smoke passed", vim.log.levels.INFO)
