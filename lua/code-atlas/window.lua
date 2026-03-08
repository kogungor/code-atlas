local M = {
  state = {
    buf = nil,
    win = nil,
    source_win = nil,
    source_buf = nil,
    line_actions = {},
    on_expand = nil,
    on_collapse = nil,
    on_refresh = nil,
    key_actions = {},
    last_lines = nil,
    highlight_ns = vim.api.nvim_create_namespace("code-atlas-window"),
    line_highlights = {},
  },
}

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function max_line_width(lines)
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end
  return max_width
end

local function dimensions(lines, ui)
  local columns = vim.o.columns
  local editor_lines = vim.o.lines - vim.o.cmdheight
  local max_width = math.max(20, math.floor(columns * ui.max_width))
  local max_height = math.max(8, math.floor(editor_lines * ui.max_height))

  local width = math.min(max_width, max_line_width(lines) + 4)
  local height = math.min(max_height, #lines + 2)

  local row = math.floor((editor_lines - height) / 2)
  local col = math.floor((columns - width) / 2)

  if row < 0 then
    row = 0
  end
  if col < 0 then
    col = 0
  end

  return width, height, row, col
end

local function ensure_buffer()
  if is_valid_buf(M.state.buf) then
    return M.state.buf
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "code-atlas", { buf = buf })
  M.state.buf = buf
  return buf
end

local function set_buffer_content(buf, lines)
  if M.state.last_lines and #M.state.last_lines == #lines then
    local same = true
    for i = 1, #lines do
      if M.state.last_lines[i] ~= lines[i] then
        same = false
        break
      end
    end
    if same then
      return
    end
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  M.state.last_lines = vim.deepcopy(lines)
end

local function apply_line_highlights(buf, line_highlights)
  vim.api.nvim_buf_clear_namespace(buf, M.state.highlight_ns, 0, -1)
  for _, item in ipairs(line_highlights or {}) do
    if item and item.line then
      local line = math.max(1, tonumber(item.line) or 1)
      local group = item.group or "Search"
      vim.api.nvim_buf_add_highlight(buf, M.state.highlight_ns, group, line - 1, 0, -1)
    end
  end
end

local function set_window_keymaps(buf)
  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, opts)
  vim.keymap.set("n", "<CR>", function()
    M.jump_to_node()
  end, opts)
  vim.keymap.set("n", "o", function()
    M.jump_to_node()
  end, opts)
  vim.keymap.set("n", "l", function()
    M.expand_node()
  end, opts)
  vim.keymap.set("n", "<Right>", function()
    M.expand_node()
  end, opts)
  vim.keymap.set("n", "h", function()
    M.collapse_node()
  end, opts)
  vim.keymap.set("n", "<Left>", function()
    M.collapse_node()
  end, opts)
  vim.keymap.set("n", "<Tab>", function()
    M.toggle_node()
  end, opts)
  vim.keymap.set("n", "r", function()
    M.refresh()
  end, opts)

  for key, handler in pairs(M.state.key_actions or {}) do
    if type(handler) == "function" then
      vim.keymap.set("n", key, handler, opts)
    end
  end
end

function M.open(lines, opts)
  local config = require("code-atlas.config").get()
  local ui = config.ui or {}
  local merged_ui = {
    border = ui.border or "rounded",
    max_width = ui.max_width or 0.8,
    max_height = ui.max_height or 0.8,
  }

  opts = opts or {}
  M.state.source_win = opts.source_win
  M.state.source_buf = opts.source_buf
  M.state.line_actions = opts.line_actions or {}
  M.state.on_expand = opts.on_expand
  M.state.on_collapse = opts.on_collapse
  M.state.on_refresh = opts.on_refresh
  M.state.key_actions = opts.key_actions or {}
  M.state.line_highlights = opts.line_highlights or {}

  local buf = ensure_buffer()
  local width, height, row, col = dimensions(lines, merged_ui)

  set_buffer_content(buf, lines)

  if is_valid_win(M.state.win) then
    vim.api.nvim_win_set_buf(M.state.win, buf)
    vim.api.nvim_win_set_config(M.state.win, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = merged_ui.border,
      title = opts.title or " code-atlas ",
      title_pos = "center",
    })
  else
    M.state.win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = merged_ui.border,
      title = opts.title or " code-atlas ",
      title_pos = "center",
    })
  end

  vim.api.nvim_set_option_value("wrap", false, { win = M.state.win })
  vim.api.nvim_set_option_value("cursorline", true, { win = M.state.win })
  apply_line_highlights(buf, M.state.line_highlights)
  set_window_keymaps(buf)
end

local function action_under_cursor()
  if not is_valid_win(M.state.win) then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(M.state.win)[1]
  return M.state.line_actions[line]
end

function M.jump_to_node()
  if not is_valid_win(M.state.win) then
    return
  end

  local action = action_under_cursor()
  local target = action and action.target
  if not target then
    vim.notify("code-atlas: no jump target on this line", vim.log.levels.WARN)
    return
  end

  local source_win = M.state.source_win
  local source_buf = M.state.source_buf

  M.close()

  require("code-atlas.navigation").jump_to_target(target, source_win, source_buf)
end

function M.expand_node()
  local action = action_under_cursor()
  if not action or not action.node_name then
    vim.notify("code-atlas: no expandable node on this line", vim.log.levels.WARN)
    return
  end

  if type(M.state.on_expand) == "function" then
    M.state.on_expand(action.node_name, action.depth or 0)
  end
end

function M.collapse_node()
  local action = action_under_cursor()
  if not action or not action.node_name then
    vim.notify("code-atlas: no collapsible node on this line", vim.log.levels.WARN)
    return
  end

  if type(M.state.on_collapse) == "function" then
    M.state.on_collapse(action.node_name)
  end
end

function M.toggle_node()
  local action = action_under_cursor()
  if not action or not action.node_name or not action.expandable then
    vim.notify("code-atlas: no toggle target on this line", vim.log.levels.WARN)
    return
  end

  if action.expanded then
    M.collapse_node()
  else
    M.expand_node()
  end
end

function M.refresh()
  if type(M.state.on_refresh) == "function" then
    M.state.on_refresh()
  else
    vim.notify("code-atlas: refresh handler unavailable", vim.log.levels.WARN)
  end
end

function M.close()
  if is_valid_win(M.state.win) then
    vim.api.nvim_win_close(M.state.win, true)
  end
  M.state.win = nil
  M.state.line_actions = {}
  M.state.on_expand = nil
  M.state.on_collapse = nil
  M.state.on_refresh = nil
  M.state.key_actions = {}
  M.state.line_highlights = {}
  M.state.last_lines = nil
end

function M.get_state()
  return {
    buf = M.state.buf,
    win = M.state.win,
    source_win = M.state.source_win,
    source_buf = M.state.source_buf,
    line_actions = M.state.line_actions,
  }
end

return M
