#!/usr/bin/env bash

# Installs a bunch of common packages. Installs Oh My Zsh and sets it as the default shell.
# Run as-is or pass in additional packages as arguments.

set -euo pipefail

COMMON_PACKAGES=(
  git
  curl
  wget
  build-essential # gcc, make, etc.
  python3
  python3-pip
  ripgrep
  fzf
  unzip
  zsh
  software-properties-common
  stow
  xsel
  xclip
  fd-find
)

install_packages() {
  local pkgs=("${COMMON_PACKAGES[@]}")
  if [[ $# -gt 0 ]]; then
    pkgs+=("$@")
  fi

  echo "[+] Installing packages: ${pkgs[*]}"
  sudo apt-get update -qq
  sudo apt-get install -y "${pkgs[@]}"
}

install_oh_my_zsh() {
  # Skip if zsh isn’t present (shouldn’t happen) or OMZ already installed
  if ! command -v zsh &>/dev/null; then
    echo "[!] zsh not found; skipping Oh My Zsh install" >&2
    return
  fi
  if [[ -d "$HOME/.oh-my-zsh" ]]; then
    echo "[✓] Oh My Zsh already present; skipping"
    return
  fi

  echo "[+] Installing Oh My Zsh (unattended)"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

set_default_shell_to_zsh() {
  local username="$(id -un 2>/dev/null || true)"
  if [[ -z "$username" ]]; then
    echo "[!] Could not determine current username—skipping chsh" >&2
    return
  fi
  if [[ "$SHELL" != *"zsh"* ]]; then
    echo "[+] Changing default shell to $(command -v zsh) for $username"
    sudo chsh -s "$(command -v zsh)" "$username" || {
      echo "[!] Could not change default shell (permissions?). You may need to do it manually." >&2
    }
  fi
}

main() {
  install_packages "$@"
  install_oh_my_zsh
  set_default_shell_to_zsh
  echo "[✓] Baseline setup complete. Open a new terminal to start using Zsh."
}

main "$@"
