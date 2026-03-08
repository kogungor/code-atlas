local M = {}

M.defaults = {
  depth_limit = 2,
  lsp = {
    enabled = true,
    timeout_ms = 1200,
    prefer_call_hierarchy = false,
    include_external = false,
  },
  layout = {
    algorithm = "hierarchical",
    spacing_x = 220,
    spacing_y = 90,
    force_iterations = 24,
  },
  ui = {
    border = "rounded",
    max_width = 0.8,
    max_height = 0.8,
    mode = "tree",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

function M.get()
  return M.options
end

return M
