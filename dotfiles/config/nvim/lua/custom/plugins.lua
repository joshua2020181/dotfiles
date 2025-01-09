local treesitter = require "plugins.configs.treesitter"

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
    'rust-lang/rust.vim',
  },
  {
    'mrcjkb/rustaceanvim',
    version = '^4', -- Recommended
    lazy = false,   -- This plugin is already lazy
  },
  {
    "mfussenegger/nvim-dap",
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
        "lua-language-server",
        "pyright",
        "pylint",
        "black",
        "isort",
        "clangd",
        "prettier",
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
  },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = vim.tbl_deep_extend("force", treesitter, {
      ensure_installed = {
        "lua",
        "python",
        "json",
        "yaml",
        "bash",
        "dockerfile",
        "rust",
        "markdown",
        "markdown_inline",
      },
      highlight = {
        enable = true,
      },
      indent = { enable = true },
    }),
  },

  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    cmd = "Telescope",
    init = function()
      require("core.utils").load_mappings "telescope"
    end,
    opts = function()
      return {
        defaults = {
          vimgrep_arguments = {
            'rg',
            '--color=never',
            '--no-heading',
            '--with-filename',
            '--line-number',
            '--column',
            '--smart-case'
          },
          prompt_prefix = "> ",
          selection_caret = "> ",
          entry_prefix = "  ",
          initial_mode = "insert",
          selection_strategy = "reset",
          sorting_strategy = "descending",
          layout_strategy = "horizontal",
          layout_config = {
            horizontal = {
              mirror = false,
            },
            vertical = {
              mirror = false,
            },
          },
          file_sorter = require 'telescope.sorters'.get_fuzzy_file,
          file_ignore_patterns = {},
          generic_sorter = require 'telescope.sorters'.get_generic_fuzzy_sorter,
          path_display = { "truncate" },
          winblend = 0,
          border = {},
          borderchars = { '|', '|', '|', '|', '|', '|', '|', '|' },
          color_devicons = true,
          use_less = true,
          set_env = { ['COLORTERM'] = 'truecolor' },
          file_previewer = require 'telescope.previewers'.vim_buffer_cat.new,
          grep_previewer = require 'telescope.previewers'.vim_buffer_vimgrep.new,
          qflist_previewer = require 'telescope.previewers'.vim_buffer_qflist.new,
          buffer_previewer_maker = require 'telescope.previewers'.buffer_previewer_maker
        },
        extensions_list = { "fzf" },
      }
    end,
    config = function(_, opts)
      dofile(vim.g.base46_cache .. "telescope")
      local telescope = require "telescope"
      telescope.setup(opts)

      -- load extensions
      for _, ext in ipairs(opts.extensions_list) do
        telescope.load_extension(ext)
      end
    end,
  },
  {
    "nvim-telescope/telescope-fzf-native.nvim",
    build =
    'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release && cmake --install build --prefix build'
  },
  {
    "epwalsh/obsidian.nvim",
    version = "*", -- recommended, use latest release instead of latest commit
    lazy = true,
    ft = "markdown",
    -- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
    -- event = {
    --   -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
    --   -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/**.md"
    --   "BufReadPre path/to/my-vault/**.md",
    --   "BufNewFile path/to/my-vault/**.md",
    -- },
    dependencies = {
      -- Required.
      "nvim-lua/plenary.nvim",

    },
    opts = {
      workspaces = {
        {
          name = "personal",
          path = "~/obsidian-notes/",
        },
      },

    },
  },
  {
    "Darazaki/indent-o-matic",
    lazy = false,
  },
  {
    "smbl64/vim-black-macchiato",
    lazy = false,
  },
  {
    "SmiteshP/nvim-navic",
  },
}

return plugins
