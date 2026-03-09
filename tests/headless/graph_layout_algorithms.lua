local root = vim.fn.getcwd()
local sample = root .. "/playground/samples/checkout_flow.lua"

local atlas = require("code-atlas")
atlas.setup({
  depth_limit = 2,
  layout = {
    algorithm = "hierarchical",
    force_iterations = 12,
  },
})

atlas.build_project_index({ root = root })

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local line = vim.fn.search("^function M\\.checkout", "nw")
if line == 0 then
  error("feature19 smoke failed: could not locate M.checkout")
end
vim.api.nvim_win_set_cursor(0, { line, 2 })

atlas.run_project_call_graph()

local window = require("code-atlas.window")
local state = window.get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature19 smoke failed: project graph window was not created")
end

local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local text = table.concat(lines, "\n")
if not text:find("layout: hierarchical", 1, true) then
  error("feature19 smoke failed: project graph output missing layout metadata line")
end

if state.source_win and vim.api.nvim_win_is_valid(state.source_win) then
  vim.api.nvim_set_current_win(state.source_win)
  vim.api.nvim_win_set_cursor(0, { line, 2 })
end

local json_path = vim.fn.tempname() .. ".json"
local json_result, json_err = atlas.run_graph_export({ "json", json_path })
if not json_result then
  error("feature19 smoke failed: json export failed: " .. tostring(json_err))
end

local json_text = table.concat(vim.fn.readfile(json_path), "\n")
local payload = vim.json.decode(json_text)
if not payload or not payload.layout then
  error("feature19 smoke failed: json export missing layout payload")
end
if payload.layout.algorithm ~= "hierarchical" then
  error("feature19 smoke failed: expected hierarchical json layout")
end

local has_position = false
for _, node in ipairs(payload.nodes or {}) do
  if node.layout and node.layout.x ~= nil and node.layout.y ~= nil then
    has_position = true
    break
  end
end
if not has_position then
  error("feature19 smoke failed: json export nodes missing layout coordinates")
end

local dot_path = vim.fn.tempname() .. ".dot"
local dot_result, dot_err = atlas.run_graph_export({ "graphviz", dot_path, "layout=force" })
if not dot_result then
  error("feature19 smoke failed: graphviz force export failed: " .. tostring(dot_err))
end

local dot_text = table.concat(vim.fn.readfile(dot_path), "\n")
if not dot_text:find("layout=neato;", 1, true) then
  error("feature19 smoke failed: graphviz force export missing neato layout")
end
if not dot_text:find("pos=\"", 1, true) then
  error("feature19 smoke failed: graphviz force export missing node coordinates")
end

local mmd_path = vim.fn.tempname() .. ".mmd"
local mmd_result, mmd_err = atlas.run_graph_export({ "mermaid", mmd_path, "layout=force" })
if not mmd_result then
  error("feature19 smoke failed: mermaid force export failed: " .. tostring(mmd_err))
end

local mmd_text = table.concat(vim.fn.readfile(mmd_path), "\n")
if not mmd_text:find("%% layout: force", 1, true) then
  error("feature19 smoke failed: mermaid output missing layout comment")
end
if not mmd_text:find("flowchart TD", 1, true) then
  error("feature19 smoke failed: mermaid force layout should use TD orientation")
end

vim.notify("feature19 smoke passed", vim.log.levels.INFO)
