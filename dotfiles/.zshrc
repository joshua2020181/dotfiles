# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled
# zstyle ':omz:update' mode auto
# zstyle ':omz:update' mode reminder

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

plugins=(git)
_ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
[[ -d "$_ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] && plugins+=(zsh-syntax-highlighting)
[[ -d "$_ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]     && plugins+=(zsh-autosuggestions)
[[ -d "$_ZSH_CUSTOM/plugins/you-should-use" ]]          && plugins+=(you-should-use)
unset _ZSH_CUSTOM

source $ZSH/oh-my-zsh.sh

# ── Exports ───────────────────────────────────────────────────────────────────
export XDG_CONFIG_HOME="$HOME/.config"
export EDITOR="nvim"

export PATH="$PATH:$HOME/.local/bin"
[[ -d /opt/nvim-linux64/bin ]]    && export PATH="$PATH:/opt/nvim-linux64/bin"
[[ -d $HOME/kiwi/kiwi_toolkit ]]  && export PATH="$PATH:$HOME/kiwi/kiwi_toolkit"
[[ -d $HOME/s ]]                  && export PATH="$PATH:$HOME/s"
[[ -d $HOME/balena-cli ]]         && export PATH="$PATH:$HOME/balena-cli"
[[ -d /usr/local/go/bin ]]        && export PATH="$PATH:/usr/local/go/bin"
command -v go &>/dev/null         && export PATH="$PATH:$(go env GOPATH)/bin"

export HAVOCOS_MAKE_NPROC=$(nproc)
export HAVOCOS_COLCON_NPROC=$(nproc)

export COMPOSE_BAKE=true

# ── Display / keyboard ────────────────────────────────────────────────────────
if [[ -n "$DISPLAY" ]]; then
  # Clear CapsLock state before remapping to avoid locking Ctrl
  if command -v xset &>/dev/null && command -v xdotool &>/dev/null; then
    xset q 2>/dev/null | grep -q 'Caps Lock:.*on' && xdotool key Caps_Lock
  fi
  command -v setxkbmap &>/dev/null && setxkbmap -option ctrl:nocaps
  command -v xcape &>/dev/null && { pkill xcape; xcape -e 'Control_L=Escape'; }
fi

# ── zsh-autosuggestions ───────────────────────────────────────────────────────
ZSH_AUTOSUGGEST_FILE="${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "$ZSH_AUTOSUGGEST_FILE" ]] && source "$ZSH_AUTOSUGGEST_FILE"
bindkey '\e\r' autosuggest-accept

# ── General aliases ───────────────────────────────────────────────────────────
alias python="python3"
alias notes="nvim $HOME/notes"

alias nbrc="nano ~/.bashrc"
alias sbrc="source ~/.bashrc"
alias nvzrc="nvim ~/.zshrc"
alias szrc="source ~/.zshrc"
alias tmux="tmux -f ~/.config/tmux/tmux.conf"
alias sshrm="ssh-keygen -f $HOME/.ssh/known_hosts -R"
alias dotdrop="$HOME/dotfiles/dotdrop.sh --cfg=$HOME/dotfiles/config.yaml"
alias ec2="$HOME/havocos/my_scripts/ec2.sh"

# ── Git ───────────────────────────────────────────────────────────────────────
alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gcm="git commit -m"
alias gcam="git commit -am"
alias gp="git push"
alias gpf="git push --force-with-lease"
alias gpl="git pull"
alias gpp="git pull && git push"
alias gco="git checkout"
alias gcob="git checkout -b"
alias gd="git diff"
alias gdiff="git diff"
alias glog="git log --oneline --decorate"
alias gls="git log --oneline --decorate --stat"
alias ggraph="git log --graph --oneline --decorate --all"

unalias gl 2>/dev/null
gl() {
  git pull
  if [[ -n $(git status --porcelain) ]]; then
    echo "Uncommitted changes!"
    echo $(git status --porcelain)
  fi
  if git submodule status | grep -q '^[-+]'; then
    echo "Warning: One or more submodules are not up to date!"
    git submodule status
  fi
}

# ── Docker ────────────────────────────────────────────────────────────────────
alias dps="docker ps"
unalias dlf 2>/dev/null
dlf() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: dlf <container_name_pattern> [docker logs flags]"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    return 1
  fi

  local pattern="$1"; shift

  local exact_match=$(docker ps -a --format "{{.Names}}" | grep -x "$pattern")
  if [[ -n "$exact_match" ]]; then
    docker logs -f "$exact_match" "$@"
    return 0
  fi

  local -a containers=($(docker ps -a --format "{{.Names}}" | grep -E "$pattern"))
  if [[ ${#containers[@]} -eq 0 ]]; then
    echo "No containers match: $pattern"
    return 1
  elif [[ ${#containers[@]} -eq 1 ]]; then
    docker logs -f "${containers[1]}" "$@"
  else
    echo "Select container:"
    select container in "${containers[@]}"; do
      if [[ -n "$container" ]]; then
        docker logs -f "$container" "$@"
        break
      fi
    done
  fi
}
alias drm="docker rm -f"
alias dsa="docker stop \$(docker ps -q)"
alias dsra="docker rm -f \$(docker ps -aq)"

alias dcf="docker compose -f"
alias dcl="docker compose -f docker-compose.local.yml"
dcfd() {
  local compose_file="$1"; shift
  local no_cloud=0; local -a args=()
  for arg in "$@"; do [[ "$arg" == "--no-cloud" ]] && no_cloud=1 || args+=("$arg"); done
  if (( no_cloud )); then
    local -a svcs=($(docker compose -f "$compose_file" config --services 2>/dev/null | grep -vxE 'mqtt|backend|frontend'))
    docker compose -f "$compose_file" down "${args[@]}" "${svcs[@]}"
  else
    docker compose -f "$compose_file" down "${args[@]}"
  fi
}
dcfu() {
  local compose_file="$1"; shift
  local no_cloud=0; local -a args=()
  for arg in "$@"; do [[ "$arg" == "--no-cloud" ]] && no_cloud=1 || args+=("$arg"); done
  if (( no_cloud )); then
    local -a svcs=($(docker compose -f "$compose_file" config --services 2>/dev/null | grep -vxE 'mqtt|backend|frontend'))
    docker compose -f "$compose_file" up -d "${args[@]}" "${svcs[@]}"
  else
    docker compose -f "$compose_file" up -d "${args[@]}"
  fi
}
dcfdu() {
  local compose_file="$1"; shift
  local no_cloud=0; local -a args=()
  for arg in "$@"; do [[ "$arg" == "--no-cloud" ]] && no_cloud=1 || args+=("$arg"); done
  if (( no_cloud )); then
    local -a svcs=($(docker compose -f "$compose_file" config --services 2>/dev/null | grep -vxE 'mqtt|backend|frontend'))
    docker compose -f "$compose_file" down "${args[@]}" "${svcs[@]}" && \
    docker compose -f "$compose_file" up -d "${args[@]}" "${svcs[@]}"
  else
    docker compose -f "$compose_file" down "${args[@]}" && docker compose -f "$compose_file" up -d "${args[@]}"
  fi
}

dx() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: dx <container_name_pattern>"
    docker ps --format "table {{.Names}}\t{{.Status}}"
    return 1
  fi

  local cmd=${2:-"/bin/bash"}

  local exact_match=$(docker ps --format "{{.Names}}" | grep -x "$1")
  if [[ -n "$exact_match" ]]; then
    docker exec -it "$exact_match" $cmd
    return 0
  fi

  local containers=($(docker ps --format "{{.Names}}" | grep -E "*$1*"))
  if [[ ${#containers[@]} -eq 0 ]]; then
    echo "No running containers match: $1"
    return 1
  elif [[ ${#containers[@]} -eq 1 ]]; then
    docker exec -it "${containers[1]}" $cmd
  else
    echo "Select container:"
    select container in "${containers[@]}"; do
      if [[ -n "$container" ]]; then
        docker exec -it "$container" $cmd
        break
      fi
    done
  fi
}
_dx_completion() {
  local -a containers
  containers=($(docker ps --format "{{.Names}}" 2>/dev/null))
  _describe 'containers' containers
}
compdef _dx_completion dx

builder() {
  if [[ -z "$(docker ps --filter name=^builder$ --filter status=running -q)" ]]; then
    echo "Starting builder container..."
    docker compose -f ~/havocos/my_scripts/docker-compose.yaml up -d || return 1
  fi

  if [[ "$1" == "--build" ]]; then
    if [[ "$2" == "--nproc" ]]; then
      echo "Using $3 parallel jobs for build"
      docker exec -it -e HAVOCOS_COLCON_NPROC=$3 builder /havoc/workspace/services/autonomy/scripts/build.sh
    else
      docker exec -it builder /havoc/workspace/services/autonomy/scripts/build.sh
    fi
  elif [[ "$1" == "--lint" ]]; then
    docker exec -it builder /havoc/workspace/services/autonomy/scripts/lint.sh --fix && \
      sudo chown -R "$USER:$USER" ~/havocos
  elif [[ "$1" == "--gen-protobufs" ]]; then
    docker exec -it builder /havoc/workspace/scripts/dev_gen_protobufs.sh && \
      sudo chown -R "$USER:$USER" ~/havocos
  else
    docker exec -it builder bash
  fi
}

# ── SSH helpers ───────────────────────────────────────────────────────────────
sshp() {
  local host="$1"
  local password
  if [[ "$host" == *acme* ]]; then
    password="$ACME_SSH_PASSWORD"
  else
    password="$HAVOC_SSH_PASSWORD"
  fi
  sshpass -p "$password" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@"$host" "${@:2}"
}

scpp() {
  local password
  for arg in "$@"; do
    if [[ "$arg" == *acme* ]]; then
      password="$ACME_SSH_PASSWORD"
      break
    elif [[ "$arg" == *:* ]]; then
      password="$HAVOC_SSH_PASSWORD"
      break
    fi
  done
  sshpass -p "$password" scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$@"
}

# # TODO: guard if go installed
# git config --global url."git@github.com:".insteadOf "https://github.com/"
# go env -w GOPRIVATE=github.com/HavocAI/*
# go env -w GONOSUMDB=github.com/HavocAI/*

# ── Tool sources (guarded) ────────────────────────────────────────────────────
[[ -f "$HOME/.env" ]]                               && source "$HOME/.env"
[[ -f "$HOME/.env.local" ]]                         && source "$HOME/.env.local"
[[ -f "$HOME/havocos/.env" ]]                       && source "$HOME/havocos/.env"
[[ -f "$HOME/havocos/scripts/dev_init.sh" ]]        && source "$HOME/havocos/scripts/dev_init.sh"
[[ -f "$HOME/.fzf.zsh" ]]                           && source "$HOME/.fzf.zsh"
[[ -f "$HOME/.cargo/env" ]]                         && source "$HOME/.cargo/env"

# Show machine name in right-side prompt if set in ~/.env.local
[[ -n "$MACHINE_NAME" ]] && export RPROMPT="%F{242}$MACHINE_NAME%f"

command -v zoxide  &>/dev/null && eval "$(zoxide init --cmd cd zsh)"
command -v thefuck &>/dev/null && eval "$(thefuck --alias)"

# nvm
export NVM_DIR="$HOME/.config/nvm"
[[ -s "$NVM_DIR/nvm.sh" ]]          && source "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# bun completions
[ -s "/home/joshua/.bun/_bun" ] && source "/home/joshua/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

alias claude-mem='/home/joshua/.bun/bin/bun "/home/joshua/.claude/plugins/cache/thedotmack/claude-mem/12.1.0/scripts/worker-service.cjs"'
