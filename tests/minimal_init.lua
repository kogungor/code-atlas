vim.opt.runtimepath:prepend(vim.fn.getcwd())

require("code-atlas").setup({
  depth_limit = 2,
})
