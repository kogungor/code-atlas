local root = vim.fn.getcwd()

if vim.fn.exists(":CodeAtlasHotPath") ~= 2 then
  error("feature27 smoke failed: :CodeAtlasHotPath command is not registered")
end

local atlas = require("code-atlas")
atlas.setup({
  depth_limit = 2,
  hot_path = {
    top_n = 8,
    max_depth = 3,
    path_depth = 4,
    path_count = 3,
    include_tests = false,
    include_churn = true,
    churn_limit = 20,
    churn_weight = 0.1,
    direction = "outgoing",
  },
})

local index, build_err = atlas.build_project_index({ root = root })
if not index then
  error("feature27 smoke failed: index build failed: " .. tostring(build_err))
end

local report, report_err = atlas.run_hot_path_detection({
  top_n = 6,
  max_depth = 3,
  path_depth = 4,
  path_count = 3,
  include_tests = false,
  include_churn = true,
  churn_limit = 20,
  churn_weight = 0.1,
  direction = "outgoing",
})
if not report then
  error("feature27 smoke failed: hot path detection failed: " .. tostring(report_err))
end

if not report.hotspots or #report.hotspots == 0 then
  error("feature27 smoke failed: expected non-empty hotspots")
end

if not report.hot_paths or #report.hot_paths == 0 then
  error("feature27 smoke failed: expected non-empty hot_paths")
end

vim.cmd("CodeAtlasHotPath outgoing top=6 max_depth=3 path_depth=4 path_count=3 include_tests=false include_churn=true churn_limit=20 churn_weight=0.1")

local state = require("code-atlas.window").get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature27 smoke failed: hot path window was not created")
end

local text = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
if not text:find("code%-atlas hot path detection") then
  error("feature27 smoke failed: expected hot path report title")
end
if not text:find("hotspots:", 1, true) then
  error("feature27 smoke failed: expected hotspots section")
end
if not text:find("hot_paths:", 1, true) then
  error("feature27 smoke failed: expected hot_paths section")
end
if not text:find("churn:", 1, true) then
  error("feature27 smoke failed: expected churn summary")
end
if not text:find("rationale:", 1, true) then
  error("feature27 smoke failed: expected rationale lines")
end
if not text:find("churn=", 1, true) then
  error("feature27 smoke failed: expected churn contribution in rationale")
end

vim.notify("feature27 smoke passed", vim.log.levels.INFO)
