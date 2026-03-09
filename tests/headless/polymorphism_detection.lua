local root = vim.fn.getcwd()
local sample = root .. "/playground/samples/lua_polymorphic.lua"

local atlas = require("code-atlas")
local index, err = atlas.build_project_index({ root = root })
if not index then
  error("feature22 smoke failed: " .. tostring(err))
end

local source = nil
for _, symbol in ipairs(index.by_path[sample] or {}) do
  if symbol.short_name == "calculate_dynamic" then
    source = symbol
    break
  end
end

if not source then
  error("feature22 smoke failed: calculate_dynamic symbol not found")
end

local match = nil
for _, item in ipairs(index.call_resolutions[source.id] or {}) do
  if item.call_name == "apply_discount_rules" then
    match = item
    break
  end
end

if not match then
  error("feature22 smoke failed: polymorphic call resolution entry missing")
end

if not match.polymorphic or not match.dynamic then
  error("feature22 smoke failed: call should be marked polymorphic/dynamic")
end

if not match.targets or #match.targets < 2 then
  error("feature22 smoke failed: call should include multiple targets")
end

local seen_checkout = false
local seen_audit = false
for _, target in ipairs(match.targets) do
  if target.name == "CheckoutService.apply_discount_rules" then
    seen_checkout = true
  elseif target.name == "AuditService.apply_discount_rules" then
    seen_audit = true
  end
end

if not seen_checkout or not seen_audit then
  error("feature22 smoke failed: expected both polymorphic targets")
end

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local line = vim.fn.search("^local function calculate_dynamic", "nw")
if line == 0 then
  error("feature22 smoke failed: calculate_dynamic line not found")
end
vim.api.nvim_win_set_cursor(0, { line, 2 })
atlas.run_project_call_graph()

local state = require("code-atlas.window").get_state()
local text = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
if not text:find("polymorphic_calls: ", 1, true) then
  error("feature22 smoke failed: graph missing polymorphic call summary")
end
if not text:find("%[poly:2%]") then
  error("feature22 smoke failed: graph missing polymorphic resolution hint")
end
if not text:find("alt %-%>") then
  error("feature22 smoke failed: graph missing alternative target hint")
end
if not text:find("%[dynamic%]") then
  error("feature22 smoke failed: graph missing dynamic edge hint")
end

if state.source_win and vim.api.nvim_win_is_valid(state.source_win) then
  vim.api.nvim_set_current_win(state.source_win)
end

local exported = atlas.run_graph_export({ "json", vim.fn.tempname() .. ".json" })
if not exported then
  error("feature22 smoke failed: export command failed")
end

vim.notify("feature22 smoke passed", vim.log.levels.INFO)
