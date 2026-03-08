local root = vim.fn.getcwd()

if vim.fn.exists(":CodeAtlasEvolution") ~= 2 then
  error("feature25 smoke failed: :CodeAtlasEvolution command is not registered")
end

local atlas = require("code-atlas")
atlas.setup({
  depth_limit = 2,
  evolution = {
    limit = 12,
    hotspot_limit = 5,
    include_merges = false,
    path = "lua/code-atlas",
    timeout_ms = 6000,
  },
})

local index, build_err = atlas.build_project_index({ root = root })
if not index then
  error("feature25 smoke failed: index build failed: " .. tostring(build_err))
end

local report, report_err = atlas.run_code_evolution({
  limit = 10,
  hotspot_limit = 4,
  include_merges = false,
  path = "lua/code-atlas",
})
if not report then
  error("feature25 smoke failed: evolution report failed: " .. tostring(report_err))
end

if (report.commits_count or 0) <= 0 then
  error("feature25 smoke failed: expected at least one commit in timeline")
end

if not report.timeline or #report.timeline == 0 then
  error("feature25 smoke failed: expected non-empty timeline")
end

if not report.hotspots or not report.hotspots.files then
  error("feature25 smoke failed: expected file hotspots")
end

if not report.hotspots or not report.hotspots.symbols then
  error("feature25 smoke failed: expected symbol hotspots")
end

vim.cmd("CodeAtlasEvolution limit=8 hotspot_limit=3 path=lua/code-atlas include_merges=false")

local snapshot_path = vim.fn.tempname() .. ".jsonl"
vim.cmd("CodeAtlasEvolution limit=8 hotspot_limit=3 path=lua/code-atlas include_merges=false out=" .. vim.fn.fnameescape(snapshot_path) .. " format=jsonl")

local state = require("code-atlas.window").get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature25 smoke failed: evolution window was not created")
end

local text = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
if not text:find("code%-atlas evolution graph") then
  error("feature25 smoke failed: expected evolution title")
end
if not text:find("timeline:", 1, true) then
  error("feature25 smoke failed: expected timeline section")
end
if not text:find("hotspots_files:", 1, true) then
  error("feature25 smoke failed: expected hotspots_files section")
end
if not text:find("hotspots_symbols:", 1, true) then
  error("feature25 smoke failed: expected hotspots_symbols section")
end

local snapshot = table.concat(vim.fn.readfile(snapshot_path), "\n")
if not snapshot:find('"timeline":', 1, true) then
  error("feature25 smoke failed: expected timeline in snapshot")
end
if not snapshot:find('"hotspots":', 1, true) then
  error("feature25 smoke failed: expected hotspots in snapshot")
end

vim.notify("feature25 smoke passed", vim.log.levels.INFO)
