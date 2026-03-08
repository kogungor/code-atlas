local root = vim.fn.getcwd()
local sample = root .. "/playground/samples/lua_sample.lua"

local atlas = require("code-atlas")

atlas.setup({
  depth_limit = 2,
  ui = {
    mode = "tree",
  },
})

vim.cmd("edit " .. vim.fn.fnameescape(sample))
local run_line = vim.fn.search("^function M\\.run", "nw")
if run_line == 0 then
  error("feature17 smoke failed: could not locate M.run")
end
vim.api.nvim_win_set_cursor(0, { run_line, 2 })

atlas.run()

local window = require("code-atlas.window")
local state = window.get_state()
if not state.win or not vim.api.nvim_win_is_valid(state.win) then
  error("feature17 smoke failed: tree ui window not created")
end

local function line_index(lines, needle)
  for i, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      return i
    end
  end
  return nil
end

local tree_lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
local greet_line = line_index(tree_lines, "greet")
if not greet_line then
  error("feature17 smoke failed: greet node missing in tree mode")
end

vim.api.nvim_win_set_cursor(state.win, { greet_line, 0 })
window.toggle_node()

local expanded_lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
if not line_index(expanded_lines, "format_name") then
  error("feature17 smoke failed: toggle expand did not reveal format_name")
end

window.refresh()

atlas.set_ui_mode("ascii")

if state.source_win and vim.api.nvim_win_is_valid(state.source_win) then
  vim.api.nvim_set_current_win(state.source_win)
end

vim.cmd("edit " .. vim.fn.fnameescape(sample))
vim.api.nvim_win_set_cursor(0, { run_line, 2 })
atlas.run()

local state_ascii = window.get_state()
local ascii_lines = vim.api.nvim_buf_get_lines(state_ascii.buf, 0, -1, false)
local text = table.concat(ascii_lines, "\n")

if not text:find("calls:", 1, true) then
  error("feature17 smoke failed: ascii fallback did not render call list")
end

if not text:find("greet", 1, true) then
  error("feature17 smoke failed: ascii fallback missing greet")
end

if text:find("graph:", 1, true) then
  error("feature17 smoke failed: ascii fallback should not render interactive tree section")
end

atlas.set_ui_mode("tree")
vim.notify("feature17 smoke passed", vim.log.levels.INFO)
