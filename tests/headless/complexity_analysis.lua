local root = vim.fn.getcwd()

if vim.fn.exists(":CodeAtlasComplexity") ~= 2 then
  error("feature28 smoke failed: :CodeAtlasComplexity command is not registered")
end

local atlas = require("code-atlas")
atlas.setup({
  depth_limit = 2,
  complexity = {
    top_n = 12,
    scc_limit = 8,
    include_tests = false,
    export_format = "json",
  },
})

local index, build_err = atlas.build_project_index({ root = root })
if not index then
  error("feature28 smoke failed: index build failed: " .. tostring(build_err))
end

local report, report_err = atlas.run_complexity_analysis({
  top_n = 10,
  scc_limit = 6,
  include_tests = false,
})
if not report then
  error("feature28 smoke failed: complexity report failed: " .. tostring(report_err))
end

if not report.hotspots or #report.hotspots == 0 then
  error("feature28 smoke failed: expected non-empty hotspots")
end

if not report.sccs or #report.sccs == 0 then
  error("feature28 smoke failed: expected non-empty sccs")
end

local snapshot_path = vim.fn.tempname() .. ".json"
vim.cmd("CodeAtlasComplexity top=10 scc_limit=6 include_tests=false path=" .. vim.fn.fnameescape(snapshot_path) .. " format=json")

local state = require("code-atlas.window").get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature28 smoke failed: complexity window was not created")
end

local text = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
if not text:find("code%-atlas complexity analysis") then
  error("feature28 smoke failed: expected complexity report title")
end
if not text:find("hotspots:", 1, true) then
  error("feature28 smoke failed: expected hotspots section")
end
if not text:find("sccs:", 1, true) then
  error("feature28 smoke failed: expected sccs section")
end
if not text:find("clusters:", 1, true) then
  error("feature28 smoke failed: expected clusters section")
end
if not text:find("severity:", 1, true) then
  error("feature28 smoke failed: expected severity line")
end
if not text:find("suggestions:", 1, true) then
  error("feature28 smoke failed: expected suggestions section")
end

local json_text = table.concat(vim.fn.readfile(snapshot_path), "\n")
if not json_text:find('"structural_complexity_score":', 1, true) then
  error("feature28 smoke failed: expected structural_complexity_score in snapshot")
end
if not json_text:find('"scc_count":', 1, true) then
  error("feature28 smoke failed: expected scc_count in snapshot")
end
if not json_text:find('"structural_complexity_severity":', 1, true) then
  error("feature28 smoke failed: expected structural_complexity_severity in snapshot")
end
if not json_text:find('"suggestions":', 1, true) then
  error("feature28 smoke failed: expected suggestions in snapshot")
end

vim.notify("feature28 smoke passed", vim.log.levels.INFO)
