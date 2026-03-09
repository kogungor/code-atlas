local root = vim.fn.getcwd()

if vim.fn.exists(":CodeAtlasRiskMap") ~= 2 then
  error("risk_map_report smoke failed: :CodeAtlasRiskMap command is not registered")
end

local atlas = require("code-atlas")
atlas.setup({
  risk_map = {
    top_n = 10,
    include_tests = false,
    include_churn = true,
    churn_limit = 20,
    weight_hot_path = 1.2,
    weight_complexity = 1.0,
    weight_architecture = 1.6,
    weight_churn = 0.25,
    export_format = "json",
  },
})

local index, build_err = atlas.build_project_index({ root = root })
if not index then
  error("risk_map_report smoke failed: index build failed: " .. tostring(build_err))
end

local report, report_err = atlas.run_risk_map({
  top_n = 8,
  include_tests = false,
  include_churn = true,
  churn_limit = 20,
  churn_weight = 0.25,
})
if not report then
  error("risk_map_report smoke failed: risk map failed: " .. tostring(report_err))
end

if not report.risk_hotspots or #report.risk_hotspots == 0 then
  error("risk_map_report smoke failed: expected non-empty risk_hotspots")
end

if not report.module_risk or #report.module_risk == 0 then
  error("risk_map_report smoke failed: expected non-empty module_risk")
end

local baseline_path = vim.fn.tempname() .. "-baseline.json"
vim.cmd("CodeAtlasRiskMap top=8 include_tests=false include_churn=true churn_limit=20 churn_weight=0.25 path=" .. vim.fn.fnameescape(baseline_path) .. " format=json")

local snapshot_path = vim.fn.tempname() .. ".json"
vim.cmd(
  "CodeAtlasRiskMap top=8 include_tests=false include_churn=true churn_limit=20 churn_weight=0.25 baseline_path="
    .. vim.fn.fnameescape(baseline_path)
    .. " path="
    .. vim.fn.fnameescape(snapshot_path)
    .. " format=json"
)

local state = require("code-atlas.window").get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("risk_map_report smoke failed: risk map window was not created")
end

local text = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
if not text:find("code%-atlas risk map") then
  error("risk_map_report smoke failed: expected report title")
end
if not text:find("risk_hotspots:", 1, true) then
  error("risk_map_report smoke failed: expected risk_hotspots section")
end
if not text:find("module_risk:", 1, true) then
  error("risk_map_report smoke failed: expected module_risk section")
end
if not text:find("risk_severity:", 1, true) then
  error("risk_map_report smoke failed: expected risk_severity line")
end
if not text:find("suggestions:", 1, true) then
  error("risk_map_report smoke failed: expected suggestions section")
end
if not text:find("trend:", 1, true) then
  error("risk_map_report smoke failed: expected trend section")
end

local snapshot = table.concat(vim.fn.readfile(snapshot_path), "\n")
if not snapshot:find('"risk_hotspots":', 1, true) then
  error("risk_map_report smoke failed: expected risk_hotspots in snapshot")
end
if not snapshot:find('"module_risk":', 1, true) then
  error("risk_map_report smoke failed: expected module_risk in snapshot")
end
if not snapshot:find('"risk_severity":', 1, true) then
  error("risk_map_report smoke failed: expected risk_severity in snapshot")
end
if not snapshot:find('"suggestions":', 1, true) then
  error("risk_map_report smoke failed: expected suggestions in snapshot")
end
if not snapshot:find('"trend":', 1, true) then
  error("risk_map_report smoke failed: expected trend in snapshot")
end

vim.notify("risk_map_report smoke passed", vim.log.levels.INFO)
