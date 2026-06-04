# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Packages

| Package | Stows to |
|---------|----------|
| `dotfiles` | `~/.zshrc`, `~/.env.local.template`, `~/.gh_token` |
| `nvim` | `~/.config/nvim/` |
| `tmux` | `~/.config/tmux/` |
| `clangd` | `~/.config/clangd/` |

## New machine setup

### 1. Install basics

Installs zsh, stow, oh-my-zsh, fzf, ripgrep, and sets zsh as the default shell:

```bash
bash setup_scripts/install_basics.sh
```

### 2. Install custom tools

Installs neovim, tmux plugins, zsh plugins (syntax highlighting, autosuggestions,
you-should-use), nerd fonts, zoxide, thefuck, rust, node, and dev linters:

```bash
bash setup_scripts/install_custom.sh
```

### 3. Clone and stow

```bash
git clone git@github.com:josh-havoc/dotfiles.git ~/dotfiles
cd ~/dotfiles
git submodule update --init --recursive
bash setup_dotfiles.sh
```

The setup script will:
- Back up any conflicting files (e.g. `~/.zshrc` → `~/.zshrc.bak`)
- Stow all packages
- Create `~/.env.local` from the template and prompt for a machine name

### 4. Finish up

Open a new shell, then install tmux plugins:

```
tmux
# inside tmux: prefix + I  (capital i) to install plugins
```

## Machine-local config

`~/.env.local` holds machine-specific variables and is never committed. It is
created automatically from `~/.env.local.template` by `setup_dotfiles.sh`.

```bash
# ~/.env.local
MACHINE_NAME="laptop"   # shown greyed-out in the right-side prompt
```

To edit it:

```bash
nvim ~/.env.local && source ~/.zshrc
```

## Adding a new dotfile

Move the real file into the appropriate package directory, then restow:

```bash
mv ~/.somerc ~/dotfiles/dotfiles/.somerc
cd ~/dotfiles && stow --restow dotfiles
```

## Re-running setup on an existing machine

`setup_dotfiles.sh` is idempotent — safe to re-run. It backs up conflicts and
skips `.env.local` if it already exists.

```bash
bash ~/dotfiles/setup_dotfiles.sh
```
