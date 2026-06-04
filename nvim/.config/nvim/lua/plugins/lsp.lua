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
          cmd = { "clangd", "--fallback-style=Google" },
          filetypes = { "c", "cpp", "objc", "objcpp" },
          on_new_config = function(new_config, new_root_dir)
            if new_root_dir and new_root_dir:find("havocos", 1, true) then
              local result = vim.fn.system("docker inspect -f {{.State.Running}} builder 2>/dev/null")
              if vim.trim(result) == "true" then
                new_config.cmd = {
                  "docker", "exec", "-i", "builder", "clangd",
                  "--background-index",
                  "--fallback-style=Google",
                  "--path-mappings=/home/joshua/havocos=/havoc/workspace",
                }
                return
              end
              vim.notify("havocos: builder container not running, falling back to local clangd", vim.log.levels.WARN)
            end
            new_config.cmd = { "clangd", "--fallback-style=Google" }
          end,
        },

        bufls = {
          cmd = { "bufls", "serve" },
          filetypes = { "proto" },
          root_dir = require("lspconfig.util").root_pattern("buf.yaml", "buf.gen.yaml", ".git"),
        },
        -- gopls = {
        --   cmd = { 'gopls' },
        --   filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
        --   root_dir = require('lspconfig.util').root_pattern('go.work', 'go.mod', '.git'),
        -- },
      },
    },
  },
}
