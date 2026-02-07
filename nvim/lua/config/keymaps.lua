vim.g.mapleader = " "
vim.g.maplocalleader = ","

vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })

-- Diagnostics
vim.keymap.set(
  "n",
  "gl",
  vim.diagnostic.open_float,
  { desc = "Show diagnostic under cursor" }
)

vim.keymap.set(
  "n",
  "<leader>e",
  function()
    vim.diagnostic.open_float({ focus = true })
  end,
  { desc = "Show diagnostic (focused)" }
)

vim.keymap.set(
  "n",
  "[d",
  vim.diagnostic.goto_prev,
  { desc = "Previous diagnostic" }
)

vim.keymap.set(
  "n",
  "]d",
  vim.diagnostic.goto_next,
  { desc = "Next diagnostic" }
)

-- Code Action to apply fixes from lint/lsp
vim.keymap.set(
  "n",
  "<leader>ca",
  vim.lsp.buf.code_action,
  { desc = "Code action" }
)

