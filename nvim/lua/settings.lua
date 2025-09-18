local o = vim.opt

o.number = true
o.relativenumber = true

o.expandtab = true
o.shiftwidth = 2

vim.keymap.set("i", "jj", "<Esc>")

vim.cmd('filetype plugin indent on')
vim.cmd('syntax enable')
