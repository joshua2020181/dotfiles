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

plugins=(
  git
  zsh-syntax-highlighting
  zsh-autosuggestions
  you-should-use
)

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
  command -v setxkbmap &>/dev/null && setxkbmap -option ctrl:nocaps
  command -v xcape     &>/dev/null && xcape -e 'Control_L=Escape'
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
alias dlf="docker logs -f"
alias drm="docker rm -f"
alias dsa="docker stop \$(docker ps -q)"
alias dsra="docker rm -f \$(docker ps -aq)"

alias dcf="docker compose -f"
alias dcl="docker compose -f docker-compose.local.yml"
dcfd() { docker compose -f "$1" down "${@:2}"; }
dcfu() { docker compose -f "$1" up -d "${@:2}"; }
dcfdu() { docker compose -f "$1" down "${@:2}" && docker compose -f "$1" up -d "${@:2}"; }

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
    root@"$host"
}

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
