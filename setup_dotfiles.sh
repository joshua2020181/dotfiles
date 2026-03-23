#!/usr/bin/env bash
# setup_dotfiles.sh — Stow all dotfile packages and bootstrap machine-local config.
#
# Usage:
#   bash setup_dotfiles.sh          # stow everything, prompt for MACHINE_NAME
#   bash setup_dotfiles.sh --no-prompt  # non-interactive (CI / remote bootstrap)
#
# Requires: stow (installed by setup_scripts/install_basics.sh)

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT=true
[[ "${1:-}" == "--no-prompt" ]] && PROMPT=false

# Packages to stow (each is a subdirectory of $DOTFILES_DIR)
PACKAGES=(dotfiles nvim tmux clangd)

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo "[+] $*"; }
success() { echo "[✓] $*"; }
warn()    { echo "[!] $*" >&2; }

require_stow() {
  if ! command -v stow &>/dev/null; then
    warn "stow not found. Install it first:"
    warn "  sudo apt-get install -y stow   (or run setup_scripts/install_basics.sh)"
    exit 1
  fi
}

# Back up a file/symlink that would block stow, then remove it so stow can proceed.
backup_and_remove() {
  local target="$1"
  if [[ -e "$target" && ! -L "$target" ]]; then
    local backup="${target}.bak"
    warn "Backing up existing $target → $backup"
    mv "$target" "$backup"
  elif [[ -L "$target" ]]; then
    info "Removing stale symlink $target"
    rm "$target"
  fi
}

stow_package() {
  local pkg="$1"
  local pkg_dir="$DOTFILES_DIR/$pkg"

  if [[ ! -d "$pkg_dir" ]]; then
    warn "Package '$pkg' not found at $pkg_dir — skipping"
    return
  fi

  # Dry-run to find conflicts, then back them up
  local conflicts
  conflicts=$(stow --dir="$DOTFILES_DIR" --target="$HOME" --no-folding -n "$pkg" 2>&1 | grep "existing target" | awk '{print $NF}' || true)
  for rel in $conflicts; do
    backup_and_remove "$HOME/$rel"
  done

  stow --dir="$DOTFILES_DIR" --target="$HOME" --no-folding "$pkg"
  success "Stowed $pkg"
}

bootstrap_env_local() {
  local template="$HOME/.env.local.template"
  local env_local="$HOME/.env.local"

  if [[ ! -f "$template" ]]; then
    warn ".env.local.template not found — skipping .env.local setup"
    return
  fi

  if [[ -f "$env_local" ]]; then
    success ".env.local already exists — skipping"
    return
  fi

  cp "$template" "$env_local"

  if [[ "$PROMPT" == true ]]; then
    echo ""
    read -r -p "Enter a short name for this machine (shown in prompt, e.g. laptop/ec2): " machine_name
    if [[ -n "$machine_name" ]]; then
      sed -i "s/MACHINE_NAME=.*/MACHINE_NAME=\"$machine_name\"/" "$env_local"
      success "Created ~/.env.local with MACHINE_NAME=\"$machine_name\""
    else
      success "Created ~/.env.local from template (edit it to set MACHINE_NAME)"
    fi
  else
    success "Created ~/.env.local from template (edit it to set MACHINE_NAME)"
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
require_stow

info "Stowing dotfile packages: ${PACKAGES[*]}"
for pkg in "${PACKAGES[@]}"; do
  stow_package "$pkg"
done

bootstrap_env_local

echo ""
success "Done. Open a new shell (or: source ~/.zshrc) to pick up all changes."
