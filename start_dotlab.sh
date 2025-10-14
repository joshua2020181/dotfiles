#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# build_and_run.sh – Build, start, and attach to the dotlab container
# -----------------------------------------------------------------------------
# Usage:
#   ./build_and_run.sh             # builds image, (re)creates container, execs in
# -----------------------------------------------------------------------------
set -euo pipefail

IMAGE_TAG="dotlab"
CONTAINER_NAME="dotlab"

# If container exists, leave it; otherwise create it
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "[+] Container '$CONTAINER_NAME' already exists. Starting if stopped..."
  docker start "$CONTAINER_NAME" || true
else
  # Build the image
  echo "[+] Building image '$IMAGE_TAG'..."
  docker build -t "$IMAGE_TAG" .
  echo "[+] Creating and starting container '$CONTAINER_NAME'..."
  docker run -d \
    --name "$CONTAINER_NAME" \
    -v "$HOME/dotfiles:/home/joshua/dotfiles" \
    -v "$HOME/havocos:/home/joshua/havocos" \
    -v "/usr/include:/usr/include" \
    -v "/havoc:/havoc" \
    "$IMAGE_TAG" \
    tail -f /dev/null
fi

echo "Run 'cd dotfiles && stow nvim && stow tmux' to setup configs."

# Exec into it
echo "[+] Attaching to '$CONTAINER_NAME'..."
docker exec -it "$CONTAINER_NAME" zsh
