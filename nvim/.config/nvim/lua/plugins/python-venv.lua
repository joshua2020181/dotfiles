-- Auto-detect a project virtualenv (.venv) and point pyright + pylint at it,
-- so imports of packages installed only in the venv resolve correctly.
--
-- Searches upward from the current file for the nearest directory containing
-- a `.venv` (so e.g. havocos/sitl/.venv is found for files under sitl/).

local function find_venv(from)
  local root = vim.fs.root(from or 0, ".venv")
  if not root then
    return nil
  end
  local venv = root .. "/.venv"
  if vim.fn.isdirectory(venv) == 1 then
    return venv
  end
  return nil
end

return {
  -- pyright: use the venv's interpreter for analysis.
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = {
          before_init = function(_, config)
            local venv = find_venv(config.root_dir)
            if venv then
              config.settings = config.settings or {}
              config.settings.python = config.settings.python or {}
              config.settings.python.pythonPath = venv .. "/bin/python"
              config.settings.python.venvPath = vim.fn.fnamemodify(venv, ":h")
              config.settings.python.venv = ".venv"
            end
          end,
        },
      },
    },
  },

  -- pylint (nvim-lint): the venv usually has no pylint of its own, so keep the
  -- system pylint but point it at the venv's site-packages via PYTHONPATH so it
  -- resolves packages installed only in the venv. Resolved per-buffer since the
  -- venv depends on the file. If the venv ships its own pylint, prefer that.
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "python",
        callback = function(args)
          local venv = find_venv(args.buf)
          local pylint = require("lint").linters.pylint
          if not venv then
            pylint.cmd = "pylint"
            pylint.env = nil
            return
          end
          local site = vim.fn.glob(venv .. "/lib/python*/site-packages", false, true)
          if venv and vim.fn.executable(venv .. "/bin/pylint") == 1 then
            pylint.cmd = venv .. "/bin/pylint"
            pylint.env = nil
          else
            pylint.cmd = "pylint"
            pylint.env = site[1] and { PYTHONPATH = site[1] } or nil
          end
        end,
      })
      return opts
    end,
  },
}
