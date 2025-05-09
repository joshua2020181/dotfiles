# needed to setup neovim when running in a docker container

/usr/local/bin/nvim --appimage-extract
sudo mv /usr/local/bin/nvim /usr/local/bin/nvim.appimage
sudo ln -s "$(pwd)/squashfs-root/usr/bin/nvim" /usr/local/bin/nvim
