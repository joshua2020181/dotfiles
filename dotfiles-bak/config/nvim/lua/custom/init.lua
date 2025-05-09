-- set font
vim.o.guifont = "JetBrainsMono Nerd Font:h12"

vim.opt.colorcolumn = "100"

vim.cmd('set clipboard+=unnamedplus')
vim.keymap.set('i', '<M-CR>', 'copilot#Accept("\\<CR>")', {
  expr = true,
  replace_keycodes = false,
  noremap = true,
  silent = true,
})
vim.g.copilot_no_tab_map = true
vim.g.copilot_assume_mapped = true

-- vim.g.copilot_no_enter_map = true

vim.o.termguicolors = true
vim.o.scrolloff = 5
vim.o.virtualedit = "onemore"
-- vim.cmd'colorscheme yourfavcolorscheme'

-- vim.lsp.inlay_hint.enable(true)

vim.opt.conceallevel=1

vim.opt.relativenumber = true
vim.opt.number = true
vim.o.fileencoding = "utf-16"

vim.opt.statusline = "%F"

vim.g.black_macchiato_args = "--line-length 100"

local function set_python_format_keybind()
  if vim.bo.filetype == "python" then
    vim.api.nvim_buf_set_keymap(0, "v", "<Leader>fm", ":'<, '>BlackMacchiato<CR>", { noremap = true, silent = true, desc = "format selection" })
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = set_python_format_keybind,
})

-- vim.o.winbar = "%{%v:lua.require'nvim-navic'.get_location()%}"

-- vim.o.winbar = "%=%m %f %{%v:lua.require'nvim-navic'.get_location()%}"
