#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install_custom.sh – Install custom dev tools and configs on APT hosts
# -----------------------------------------------------------------------------
# Assumes install_basics.sh has already been run.
#   $ bash install_custom.sh
#
# Installs tmux plugins, Neovim (NvChad), shell utilities, Node.js, Python 3.8,
# custom fonts, Oh My Zsh plugins, and bootstraps dotdrop.
# -----------------------------------------------------------------------------
set -euo pipefail
set -x

sudo apt-get update -qq

# 1. TPM (Tmux Plugin Manager)
if [[ ! -d "$HOME/.config/tmux/plugins/tpm" ]]; then
  echo "[+] Installing TPM (tmux plugin manager)..."
  sudo apt-get install -y tmux
  git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
else
  echo "[✓] TPM already installed."
fi

# 2. Neovim via AppImage + NvChad
if [[ ! -f "/usr/local/bin/nvim" ]]; then
  echo "[+] Installing Neovim AppImage..."
  wget -qO nvim.appimage https://github.com/neovim/neovim/releases/download/v0.11.1/nvim-linux-x86_64.appimage
  chmod u+x nvim.appimage
  sudo mv nvim.appimage /usr/local/bin/nvim
  sudo add-apt-repository -y universe
  sudo apt-get update -qq
  sudo apt-get install -y libfuse2
else
  echo "[✓] Neovim already installed."
fi

# 3. Smart CapsLock: xcape + layout
# echo "[+] Configuring smart CapsLock..."
sudo apt-get install -y xcape x11-xkb-utils
# setxkbmap -option
# setxkbmap -option 'ctrl:nocaps'
# xcape -e 'Control_L=Escape'

# 4. zoxide
if ! command -v zoxide &>/dev/null; then
  echo "[+] Installing zoxide..."
  curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
else
  echo "[✓] zoxide present."
fi

# 5. Additional cli tools: tldr, xsel
echo "[+] Installing extra CLI utils: xsel..."
sudo apt-get install -y xsel

# 6. Node.js (latest LTS + latest NPM)
echo "[+] Installing Node.js (latest LTS) via NodeSource..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "[+] Upgrading npm to the latest major version..."
sudo npm install -g npm@latest

sudo npm install -g tldr

# # 7. Python 3.8 via deadsnakes
# echo "[+] Installing Python 3.8..."
# sudo add-apt-repository -y ppa:deadsnakes/ppa
# sudo apt-get update -qq
# sudo apt-get install -y python3.8 python3.8-venv python3.8-dev

# 8. dotdrop bootstrapping
# if [[ -d "${HOME}/dotdrop" ]]; then
#   echo "[+] Bootstrapping dotdrop..."
#   pip3 install --user -r dotdrop/requirements.txt
#   bash dotdrop/bootstrap.sh
# else
#   echo "[!] dotdrop directory not found in \$HOME"
# fi

# 9. Oh My Zsh plugins
echo "[+] Installing Oh My Zsh plugins..."
ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
for repo in \
  https://github.com/zsh-users/zsh-syntax-highlighting.git \
  https://github.com/zsh-users/zsh-autosuggestions.git \
  https://github.com/MichaelAquilina/zsh-you-should-use.git; do
  plugin_dir="$ZSH_CUSTOM/plugins/$(basename $repo .git)"
  if [[ ! -d "$plugin_dir" ]]; then
    git clone --depth 1 $repo "$plugin_dir"
  else
    echo "[✓] $(basename $repo) installed."
  fi
done

# 10. Nerd Font (JetBrainsMono)
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
if [[ ! -f "$FONT_DIR/JetBrainsMonoNerdFont-Medium.ttf" ]]; then
  echo "[+] Installing JetBrainsMono Nerd Font..."
  sudo apt install -y fontconfig
  curl -sL https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip -o /tmp/jbm.zip
  unzip -qq /tmp/jbm.zip -d /tmp/jbm
  mv /tmp/jbm/*.ttf "$FONT_DIR/"
  fc-cache -f
  rm -rf /tmp/jbm*
else
  echo "[✓] Nerd font already installed."
fi

echo "[+] Installing Rust (rustup)..."
if [[ ! -x "$HOME/.cargo/bin/rustc" ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  export PATH="$HOME/.cargo/bin:$PATH"
else
  echo "[✓] Rust already installed."
fi

pip3 install thefuck --user

# linters/formatters
pip3 install pylint black isort clang-format --user
sudo apt install -y clangd clang-tidy

echo "[✓] Custom tools setup complete. Open a new shell to pick up font+zsh changes."
