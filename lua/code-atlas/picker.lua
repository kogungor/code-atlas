local M = {}

function M.function_entries(bufnr)
  local treesitter = require("code-atlas.treesitter")
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local functions, err = treesitter.list_local_functions(bufnr)
  if not functions then
    return nil, err
  end

  table.sort(functions, function(a, b)
    return a.name < b.name
  end)

  local entries = {}
  for _, fn in ipairs(functions) do
    entries[#entries + 1] = {
      name = fn.name,
      bufnr = bufnr,
      range = fn.range,
      lang = fn.lang,
    }
  end

  return entries, nil
end

return M
