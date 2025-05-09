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
  },
}
