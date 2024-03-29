local plugins = {
  {
    "dstein64/vim-startuptime",
    lazy = false,
  },
  {
    "christoomey/vim-tmux-navigator",
    lazy = false,
  },
  {
    "github/copilot.vim",
    lazy = false,
  },
  {
    "ibhagwan/fzf-lua",
    lazy = false,
  },
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "typescript-language-server",
      }
    }
  },
  {
    "neovim/nvim-lspconfig",
    init = function()
      require("core.utils").lazy_load "nvim-lspconfig"
    end,
    dependencies = {
      'jose-elias-alvarez/null-ls.nvim',
      config = function()
        require "custom.configs.null-ls"
      end,
    },
    config = function()
      require "plugins.configs.lspconfig"
      require "custom.configs.lspconfig"
    end,
  },
  -- {
  --   "neovim/nvim-lspconfig",
  --   config = function()
  --     require "plugins.configs.lspconfig"
  --     require "custom.configs.lspconfig"
  --   end,
  -- },
  {
    "kevinhwang91/promise-async",
  },
  {
    "kevinhwang91/nvim-ufo",
    lazy = false,
    requires = {
      "kevinhwang91/promise-async",
    },
    config = function()
      require "custom.configs.ufo"
    end,
  }
}

return plugins
