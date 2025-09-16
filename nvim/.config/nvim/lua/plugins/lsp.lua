return {
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "typescript-language-server",
        "lua-language-server",
        "pyright",
        "clangd",
        "prettier",
      },
    },
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        python = { "pylint" },
        typescript = { "eslint" },
        -- c = { "clangtidy" },
        -- cpp = { "clangtidy" },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        python = { "black", "isort" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        -- c = { "clang-format" },
        -- cpp = { "clang-format" },
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          cmd = {
            'clangd',
            '--query-driver=/usr/bin/gcc',
            '--fallback-style=Google',
          },
          filetypes = { 'c', 'cpp', 'objc', 'objcpp' },
        },
        bufls = {
          cmd = { 'bufls', 'serve' },
          filetypes = { 'proto' },
          root_dir = require('lspconfig.util').root_pattern('buf.yaml', 'buf.gen.yaml', '.git'),
        },
        -- gopls = {
        --   cmd = { 'gopls' },
        --   filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
        --   root_dir = require('lspconfig.util').root_pattern('go.work', 'go.mod', '.git'),
        -- },
      }
    }
  },
}
