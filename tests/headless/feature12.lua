local root = vim.fn.getcwd()
local code_atlas = require("code-atlas")

local index, err = code_atlas.build_project_index({ root = root })
if not index then
  error("feature12 smoke failed: " .. tostring(err))
end

local render_line_defs = index.by_name["render_receipt_line"] or {}
if #render_line_defs == 0 then
  error("feature12 smoke failed: render_receipt_line symbol not found")
end

local symbol = render_line_defs[1]
local resolutions = index.call_resolutions[symbol.id] or {}

local matched = nil
for _, item in ipairs(resolutions) do
  if item.call == "format_name" then
    matched = item
    break
  end
end

if not matched then
  error("feature12 smoke failed: expected call resolution entry for format_name")
end

if matched.unresolved then
  error("feature12 smoke failed: format_name should resolve cross-file")
end

if not matched.best or not matched.best.path:find("lua_sample.lua", 1, true) then
  error("feature12 smoke failed: best candidate should point to lua_sample.lua")
end

vim.cmd("edit " .. vim.fn.fnameescape(root .. "/playground/samples/checkout_flow.lua"))
local checkout_line = vim.fn.search("^function M\\.checkout", "nw")
vim.api.nvim_win_set_cursor(0, { checkout_line, 2 })
code_atlas.run_project_call_graph()

local state = require("code-atlas.window").get_state()
local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local text = table.concat(lines, "\n")
if not text:find("unresolved_calls:", 1, true) then
  error("feature12 smoke failed: unresolved call summary missing from graph")
end

vim.notify("feature12 smoke passed", vim.log.levels.INFO)
