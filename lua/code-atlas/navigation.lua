local M = {}

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

function M.jump_to_target(target, source_win, source_buf)
  if is_valid_win(source_win) then
    vim.api.nvim_set_current_win(source_win)
  end

  local target_buf = target.bufnr or source_buf
  if target.path then
    vim.cmd("edit " .. vim.fn.fnameescape(target.path))
  elseif target_buf and is_valid_buf(target_buf) then
    vim.api.nvim_win_set_buf(0, target_buf)
  end

  if target.row and target.col then
    pcall(vim.api.nvim_win_set_cursor, 0, { target.row + 1, target.col })
  end
end

return M
