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
            local function local_clangd()
              new_config.cmd = { "clangd", "--fallback-style=Google" }
            end
            if not (new_root_dir and new_root_dir:find("havocos", 1, true)) then
              return local_clangd()
            end
            -- Find the worktree root (dir containing services/autonomy) at/above
            -- the LSP root, mirroring ~/.local/bin/builder so we target the
            -- matching per-worktree container (builder-<dirname>) and map the
            -- correct host path -> /havoc/workspace.
            local ws = new_root_dir
            while ws and ws ~= "/" and vim.fn.isdirectory(ws .. "/services/autonomy") == 0 do
              ws = vim.fn.fnamemodify(ws, ":h")
            end
            if not ws or ws == "/" then
              return local_clangd()
            end
            local name = vim.fn.fnamemodify(ws, ":t"):gsub("[^%w_%.%-]", "-")
            local container = "builder-" .. name
            local running = vim.trim(
              vim.fn.system("docker inspect -f {{.State.Running}} " .. container .. " 2>/dev/null")
            )
            if running == "true" then
              new_config.cmd = {
                "docker", "exec", "-i", container, "clangd",
                "--background-index",
                "--fallback-style=Google",
                "--path-mappings=" .. ws .. "=/havoc/workspace",
              }
              return
            end
            vim.notify(
              "havocos: " .. container .. " not running, falling back to local clangd",
              vim.log.levels.WARN
            )
            return local_clangd()
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
