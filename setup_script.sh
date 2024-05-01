sudo apt update && sudo apt upgrade -y
sudo apt install -y tmux neovim python3 python3-pip curl wget

# install neovim
wget https://github.com/neovim/neovim/releases/download/stable/nvim.appimage
chmod u+x nvim.appimage
sudo mv nvim.appimage /usr/local/bin/nvim

# https://github.com/AppImage/AppImageKit/wiki/FUSE
sudo add-apt-repository universe
sudo apt install libfuse2

# install nvchad
git clone https://github.com/NvChad/NvChad ~/.config/nvim --depth 1

# smart caps lock (caps lock is escape when tapped, control when held)
sudo apt install xcape
setxkbmap -option  # clear all options
setxkbmap -option 'ctrl:nocaps'
xcape -e 'Control_L=Escape'  # caps lock is escape when tapped
# maybe this honestly i forgot: https://gist.github.com/tanyuan/55bca522bf50363ae4573d4bdcf06e2e

curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash

sudo apt install -y xsel xcape tldr
tldr --update

# install win32yank for clipboard support in neovim
# curl -sLo/tmp/win32yank.zip https://github.com/equalsraf/win32yank/releases/download/v0.0.4/win32yank-x64.zip
# unzip -p /tmp/win32yank.zip win32yank.exe > /tmp/win32yank.exe
# chmod +x /tmp/win32yank.exe
# sudo mv /tmp/win32yank.exe /usr/local/bin/



# custom nvim and tmux
# ./copy_configs.sh
# git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm  # tmux plugin manager

# bashrc, copy over and backup
# cp ~/.bashrc ~/.bashrc.bak
# cp .bashrc ~/.bashrc
# source ~/.bashrc

git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

# node mostly for gh copilot
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - &&\
sudo apt-get install -y nodejs

pip3 install --user -r dotdrop/requirements.txt
./dotdrop/bootstrap.sh

# install python 3.8
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt-get update
sudo apt-get install python3.8 python3.8-venv

# install zsh
sudo apt install -y zsh
chsh -s $(which zsh)

# omz
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# install nerd font https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip
# JetBrainsMonoNerdFont-Medium.ttf

# install kde: sudo apt install kubuntu-desktop



