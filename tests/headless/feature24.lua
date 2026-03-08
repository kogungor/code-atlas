local root = vim.fn.getcwd()

if vim.fn.exists(":CodeAtlasArchitecture") ~= 2 then
  error("feature24 smoke failed: :CodeAtlasArchitecture command is not registered")
end

local atlas = require("code-atlas")
atlas.setup({
  depth_limit = 2,
  architecture = {
    include_tests = false,
    unknown_layer_policy = "deny",
    max_violation_examples = 2,
    export_format = "json",
    layer_by_path_prefix = {
      ["playground/samples/"] = "interface",
    },
    domain_by_top_dir = {
      playground = "samplescope",
    },
    rules_mode = "merge",
  },
})

local index, build_err = atlas.build_project_index({ root = root })
if not index then
  error("feature24 smoke failed: index build failed: " .. tostring(build_err))
end

local report, report_err = atlas.run_architecture_graph({
  include_tests = false,
  unknown_layer_policy = "deny",
  max_violation_examples = 2,
})
if not report then
  error("feature24 smoke failed: architecture report failed: " .. tostring(report_err))
end

if not report.group_ids or #report.group_ids == 0 then
  error("feature24 smoke failed: expected at least one architecture group")
end

if (report.dependency_count or 0) == 0 then
  error("feature24 smoke failed: expected architecture dependencies")
end

if not report.options or report.options.layer_by_path_prefix["playground/samples/"] ~= "interface" then
  error("feature24 smoke failed: expected layer_by_path_prefix override in options")
end

if not report.options or report.options.domain_by_top_dir.playground ~= "samplescope" then
  error("feature24 smoke failed: expected domain_by_top_dir override in options")
end

if not report.severity_counts then
  error("feature24 smoke failed: expected severity_counts in report")
end

local snapshot_path = vim.fn.tempname() .. ".json"
vim.cmd("CodeAtlasArchitecture include_tests=false unknown_policy=deny max_examples=2 path=" .. vim.fn.fnameescape(snapshot_path) .. " format=json")

local state = require("code-atlas.window").get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature24 smoke failed: architecture window was not created")
end

local text = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
if not text:find("code%-atlas architecture graph") then
  error("feature24 smoke failed: architecture report title missing")
end
if not text:find("layers:", 1, true) then
  error("feature24 smoke failed: expected layers section")
end
if not text:find("groups:", 1, true) then
  error("feature24 smoke failed: expected groups section")
end
if not text:find("rule_violations:", 1, true) then
  error("feature24 smoke failed: expected rule_violations section")
end
if not text:find("unknown_layer_policy: deny", 1, true) then
  error("feature24 smoke failed: expected unknown_layer_policy in output")
end
if not text:find("severity: critical=", 1, true) then
  error("feature24 smoke failed: expected severity summary in output")
end

local json_text = table.concat(vim.fn.readfile(snapshot_path), "\n")
if not json_text:find('"violation_count":', 1, true) then
  error("feature24 smoke failed: expected violation_count in snapshot")
end
if not json_text:find('"groups":', 1, true) then
  error("feature24 smoke failed: expected groups in snapshot")
end
if not json_text:find('"severity_counts":', 1, true) then
  error("feature24 smoke failed: expected severity_counts in snapshot")
end

vim.notify("feature24 smoke passed", vim.log.levels.INFO)
