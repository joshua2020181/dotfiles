-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

map("n", "<C-h>", "<cmd> TmuxNavigateLeft<CR>", { desc = "window left", silent = true, noremap = true })
map("n", "<C-l>", "<cmd> TmuxNavigateRight<CR>", { desc = "window right", silent = true, noremap = true })
map("n", "<C-j>", "<cmd> TmuxNavigateDown<CR>", { desc = "window down", silent = true, noremap = true })
map("n", "<C-k>", "<cmd> TmuxNavigateUp<CR>", { desc = "window up", silent = true, noremap = true })

map("i", "<C-h>", "<Left>", { desc = "cursor ←", silent = true, noremap = true })
map("i", "<C-j>", "<Down>", { desc = "cursor ↓", silent = true, noremap = true })
map("i", "<C-k>", "<Up>", { desc = "cursor ↑", silent = true, noremap = true })
map("i", "<C-l>", "<Right>", { desc = "cursor →", silent = true, noremap = true })

map("n", "<Tab>", "<cmd>bnext<CR>", {
  desc = "Next Tab",
  silent = true,
  noremap = true,
})

map("n", "<S-Tab>", "<cmd>bprevious<CR>", {
  desc = "Previous Tab",
  silent = true,
  noremap = true,
})

map("n", "<leader>x", function()
  Snacks.bufdelete()
end, { desc = "Close buffer", silent = true, noremap = true })

map("n", "<C-p>", function()
  LazyVim.pick("files")
end, { desc = "Find Files", silent = true })

-- Ctrl‑G → fuzzy search within the current buffer
map("n", "<C-g>", function()
  Snacks.picker.lines()
end, { desc = "Telescope Fuzzy Find in Buffer", silent = true })

