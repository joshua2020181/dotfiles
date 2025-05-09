local M = {}

M.disabled = {
  n = {
    ["<C-j>"] = "",
  }
}

M.general = {
  n = {
    ["<C-h>"] = { "<cmd> TmuxNavigateLeft<CR>", "window left" },
    ["<C-l>"] = { "<cmd> TmuxNavigateRight<CR>", "window right" },
    ["<C-j>"] = { "<cmd> TmuxNavigateDown<CR>", "window down" },
    ["<C-k>"] = { "<cmd> TmuxNavigateUp<CR>", "window up" },
    ["<C-p>"] = { "<cmd> lua require('fzf-lua').files()<CR>", "fzf files" },
    ["<C-g>"] = { "<cmd> lua require('fzf-lua').lgrep_curbuf()<CR>", "fzf lgrep_curbuf" },

    ["gl"] = {
      function()
        vim.diagnostic.open_float(0, { scope = "line" })
      end,
      "view lsp message",
    },

    ["gh"] = {
      function()
        vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
      end,
      "toggle inlay hint",
    },
    ["fo"] = {
      function()
        return require("obsidian").util.gf_passthrough()
      end,
      opts = {
        noremap = false,
        expr = true,
        buffer = true,
      },
    },
    ["<Leader>lr"] = { "<cmd> LspRestart<CR>", "restart LSP"},
  },

  i = {
    -- ["<C-Tab>"] = {'copilot#Accept("")', "copilot accept"},
    -- ["<C-Space>"] = {'<cmd> copilot#Accept("\\<C-Space>")', "copilot accept"},
  },
}

return M
