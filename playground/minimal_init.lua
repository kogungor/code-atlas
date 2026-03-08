vim.opt.runtimepath:prepend(vim.fn.getcwd())

require("code-atlas").setup({
  depth_limit = 2,
})

vim.keymap.set("n", "<leader>cg", "<cmd>CodeAtlas<cr>", {
  desc = "Run code-atlas",
})
