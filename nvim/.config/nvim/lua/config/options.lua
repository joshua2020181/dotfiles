-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.o.guifont = "JetBrainsMono Nerd Font:h12"

vim.opt.colorcolumn = "100"

vim.cmd("set clipboard+=unnamedplus")

vim.o.termguicolors = true
vim.o.scrolloff = 5
vim.o.virtualedit = "onemore"

vim.o.wrap = true
vim.o.linebreak = true

vim.g.autoformat = false  -- disable autoformat by default

vim.diagnostic.config({
  virtual_text = {
    source = true,
  },
})
