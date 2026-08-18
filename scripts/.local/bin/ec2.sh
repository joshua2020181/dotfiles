#!/bin/bash
# ec2.sh — Manage EC2 instances (start, stop, status, dns, port forwarding)
#
# Usage: ec2.sh <action> [instance-id] [options]
#
# Instance ID is optional if $EC2_INSTANCE_ID is set.
# PEM file defaults to $EC2_PEM_FILE or ~/.ssh/josh.cheng.pem.
# SSH user defaults to $EC2_USER or ubuntu.
#
# Run 'ec2.sh --help' for full usage.

set -e

# Warn if running from inside an EC2 instance
if curl -sf -m 1 http://169.254.169.254/latest/meta-data/instance-id &>/dev/null; then
  echo "WARNING: You appear to be running this script from inside an EC2 instance."
  read -r -p "Continue anyway? [yes/N] " _confirm
  [[ "$_confirm" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

REGION="${AWS_DEFAULT_REGION:-us-east-2}"
ACTION=""
INSTANCE_ID="${EC2_INSTANCE_ID:-}"
EC2_PEM="${EC2_PEM_FILE:-$HOME/.ssh/josh.cheng.pem}"
EC2_USER="${EC2_USER:-ubuntu}"
EXTRA_ARG2=""
RECURSIVE=""

# Nicknames -> instance IDs, so e.g. `ec2 my-device ssh` works without
# looking up instance IDs. File format (whitespace-separated, # comments ok):
#   nickname  instance-id  [region]
EC2_DEVICES_FILE="${EC2_DEVICES_FILE:-$HOME/.config/ec2/devices.conf}"
declare -A DEVICE_INSTANCE_IDS
declare -A DEVICE_REGIONS
if [[ -f "$EC2_DEVICES_FILE" ]]; then
  while read -r _nick _iid _region; do
    [[ -z "$_nick" || "$_nick" == \#* ]] && continue
    DEVICE_INSTANCE_IDS["$_nick"]="$_iid"
    [[ -n "$_region" ]] && DEVICE_REGIONS["$_nick"]="$_region"
  done < "$EC2_DEVICES_FILE"
fi

# A nickname as the first arg resolves to its instance ID (and region, if
# configured) before the normal action/flag parsing below runs. A bare
# nickname with no action defaults to ssh.
if [[ $# -gt 0 && -n "${DEVICE_INSTANCE_IDS[$1]:-}" ]]; then
  INSTANCE_ID="${DEVICE_INSTANCE_IDS[$1]}"
  [[ -n "${DEVICE_REGIONS[$1]:-}" ]] && REGION="${DEVICE_REGIONS[$1]}"
  shift
  [[ $# -eq 0 ]] && set -- ssh
fi

usage() {
  cat <<EOF
Usage: ec2.sh [nickname] <action> [instance-id] [options]

A nickname (from \$EC2_DEVICES_FILE, default ~/.config/ec2/devices.conf)
resolves to an instance ID and optional region. A bare nickname with no
action defaults to ssh, e.g.:
  ec2.sh dev ssh
  ec2.sh my-device

Actions:
  devices                   List configured nicknames
  start                     Start the instance and wait until running
  stop                      Stop the instance and wait until stopped
  status                    Print the instance state
  dns                       Print the public DNS hostname
  ssh                       SSH into the instance
  sync [path]               Rsync path to ~/basename on the instance (default: \$EC2_SYNC_DIR
                            or ~/code).
                            Skips build artifacts, caches, and .venv automatically.
                            --no-git    also skip .git/ (faster code-only push)
                            --watch     watch for changes and re-sync automatically
  sync-cache                Bidirectional union of the shared ccache dir
                            (\$EC2_CCACHE_DIR or ~/.cache/ec2-ccache) with the instance. Safe
                            content-addressed merge; never deletes. Run before/
                            after an EC2 build session to share the cache.
  start-workflow            Start instance, port-forward 8080, watch-sync the sync dir, then SSH in
  port_forward <local:remote>  Forward localhost:<local> to instance:<remote>
  port_forward stop         Kill all SSH tunnels to this instance
  scp <src> <dst>           Copy files to/from instance. Prefix remote paths with ':'
                            e.g.: ec2.sh scp ./file.txt :/home/ubuntu/file.txt
                                  ec2.sh scp :/home/ubuntu/file.txt ./file.txt
                            -r    Recursive copy (for directories)
  rsync <src> <dst>         Rsync files to/from instance. Prefix remote paths with ':'
                            Compressed, progress shown, resumable (--partial).
                            e.g.: ec2.sh rsync :~/some-remote-folder ./local/path
                                  ec2.sh rsync ./local/path :/home/ubuntu/dest

Options:
  --region REGION           AWS region (default: \$AWS_DEFAULT_REGION or us-east-2)
  --pem FILE                Path to PEM key file (default: \$EC2_PEM_FILE or ~/.ssh/josh.cheng.pem)
  --user USER               SSH user (default: \$EC2_USER or ubuntu)
  --help                    Show this help message

Environment variables:
  EC2_INSTANCE_ID           Default instance ID
  EC2_PEM_FILE              Default PEM key file path
  EC2_USER                  Default SSH user
  AWS_DEFAULT_REGION        Default AWS region
  EC2_SYNC_DIR              Default path for 'sync' (default: ~/code)
  EC2_SYNC_EXTRA_EXCLUDES   Bash array of extra rsync --exclude args for 'sync'
  EC2_CCACHE_DIR            Default local ccache dir for 'sync-cache' (default: ~/.cache/ec2-ccache)
  EC2_DEVICES_FILE          Nickname -> instance ID config (default: ~/.config/ec2/devices.conf)

Examples:
  ec2.sh start
  ec2.sh status i-0abc123def456
  ec2.sh port_forward 8081:8080
  ec2.sh port_forward stop
  ec2.sh dns --region us-west-2
  ec2.sh scp ./local_file.txt :/home/ubuntu/remote_file.txt
  ec2.sh scp :/home/ubuntu/logs/ ./logs/ -r
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    devices|start|stop|status|dns|port_forward|ssh|sync|sync-cache|start-workflow|scp|rsync)
      if [[ -z "$ACTION" ]]; then ACTION="$1"; else EXTRA_ARG="$1"; fi
      shift ;;
    --region) REGION="$2"; shift 2 ;;
    --pem) EC2_PEM="$2"; shift 2 ;;
    --user) EC2_USER="$2"; shift 2 ;;
    --no-git) NO_GIT=1; shift ;;
    --watch) WATCH=1; shift ;;
    -r|--recursive) RECURSIVE=1; shift ;;
    --help) usage; exit 0 ;;
    i-*) INSTANCE_ID="$1"; shift ;;
    *)
      if [[ -z "$EXTRA_ARG" ]]; then EXTRA_ARG="$1"; else EXTRA_ARG2="$1"; fi
      shift ;;
  esac
done

# Validate
if [[ -z "$ACTION" ]]; then
  usage
  exit 1
fi

if [[ "$ACTION" == "devices" ]]; then
  if [[ ${#DEVICE_INSTANCE_IDS[@]} -eq 0 ]]; then
    echo "No devices configured in $EC2_DEVICES_FILE"
  else
    for _nick in "${!DEVICE_INSTANCE_IDS[@]}"; do
      printf '%-20s %-22s %s\n' "$_nick" "${DEVICE_INSTANCE_IDS[$_nick]}" "${DEVICE_REGIONS[$_nick]:-}"
    done | sort
  fi
  exit 0
fi

if [[ -z "$INSTANCE_ID" ]]; then
  echo "Error: no instance ID provided and \$EC2_INSTANCE_ID is not set"
  exit 1
fi

# Check aws cli is installed
if ! command -v aws &>/dev/null; then
  echo "Error: AWS CLI not found. Install it: https://aws.amazon.com/cli/"
  exit 1
fi

# Ensure SSO session is valid; log in if not
if ! aws sts get-caller-identity --region "$REGION" &>/dev/null; then
  echo "AWS SSO session expired or not logged in. Running 'aws sso login'..."
  aws sso login
fi

notify() {
  # Loud alert: desktop popup + terminal bell + message on the controlling
  # terminal (shows even during a foreground SSH session).
  local msg="$1"
  command -v notify-send &>/dev/null && notify-send -u critical "ec2.sh" "$msg" 2>/dev/null || true
  { printf '\a\n\033[1;31m[ec2.sh] %s\033[0m\n' "$msg" >/dev/tty; } 2>/dev/null || true
}

get_status() {
  AWS_PAGER="" aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].State.Name" \
    --output text
}

get_dns() {
  AWS_PAGER="" aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].PublicDnsName" \
    --output text
}

get_name() {
  AWS_PAGER="" aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value | [0]" \
    --output text 2>/dev/null
}

_name=$(get_name)
if [[ -n "$_name" && "$_name" != "None" ]]; then
  INSTANCE_LABEL="$_name ($INSTANCE_ID)"
else
  INSTANCE_LABEL="$INSTANCE_ID"
fi

case "$ACTION" in
  dns)
    get_dns
    ;;

  ssh)
    DNS=$(get_dns)
    ssh -i "$EC2_PEM" -o StrictHostKeyChecking=no "${EC2_USER}@${DNS}"
    ;;

  sync)
    SRC="${EXTRA_ARG:-${EC2_SYNC_DIR:-$HOME/code}}"
    # Replace local $HOME prefix with remote ~/ to preserve relative path
    REMOTE_PATH="~/${SRC#$HOME/}"
    DNS=$(get_dns)

    RSYNC_EXCLUDES=(
      # Build artifacts — rebuild on the remote
      --exclude="build/"
      --exclude="install/"
      --exclude="log/"
      --exclude="ccache/"
      # Large data dirs (gitignored)
      --exclude="data/"
      --exclude="logs/"
      # Python environments and caches
      --exclude=".venv/"
      --exclude="__pycache__/"
      --exclude="*.pyc"
      --exclude=".pytest_cache/"
      # Misc
      --exclude=".cache/"
      --exclude="tmp/"
    )
    # Extra project-specific excludes, e.g. EC2_SYNC_EXTRA_EXCLUDES=(--exclude="foo/")
    RSYNC_EXCLUDES+=("${EC2_SYNC_EXTRA_EXCLUDES[@]:-}")
    if [[ -n "${NO_GIT:-}" ]]; then
      RSYNC_EXCLUDES+=(--exclude=".git/")
    fi

    do_rsync() {
      local extra_flags=("$@")
      rsync -az --no-group --delete "${extra_flags[@]}" \
        --filter=':- .gitignore' \
        "${RSYNC_EXCLUDES[@]}" \
        -e "ssh -i $EC2_PEM -o StrictHostKeyChecking=no" \
        "$SRC/" "${EC2_USER}@${DNS}:${REMOTE_PATH}/"
    }

    if [[ -n "${WATCH:-}" ]]; then
      if ! command -v inotifywait &>/dev/null; then
        echo "Error: --watch requires inotifywait (sudo apt-get install -y inotify-tools)"
        exit 1
      fi
      # Regex of paths to ignore in inotifywait (mirrors RSYNC_EXCLUDES)
      INOTIFY_EXCLUDE='(/(build|install|log|ccache|data)/|/data/|/logs/|\.venv|__pycache__|\.pyc|\.pytest_cache|/\.cache/|/tmp/)'
      echo "Syncing ${SRC} -> ${EC2_USER}@${DNS}:${REMOTE_PATH}"
      echo "Watching for changes (Ctrl-C to stop)..."
      if ! do_rsync --checksum --progress; then
        notify "Initial sync failed — watch is running but files may be stale"
      fi
      # set -e is active; guard every fallible call so a transient rsync/ssh
      # error warns loudly instead of silently killing the watcher.
      while true; do
        if ! inotifywait -r -q -e modify,create,delete,move \
            --exclude "$INOTIFY_EXCLUDE" "$SRC" 2>/dev/null; then
          notify "inotifywait exited — file watch STOPPED"
          exit 1
        fi
        sleep 0.5  # brief debounce for rapid multi-file saves
        echo "[$(date +%H:%M:%S)] Change detected, syncing..."
        if ! do_rsync; then
          notify "Sync failed at $(date +%H:%M:%S) — edits may not be on the instance"
        fi
      done
    else
      echo "Syncing ${SRC} -> ${EC2_USER}@${DNS}:${REMOTE_PATH}"
      do_rsync --checksum --progress
    fi
    ;;

  sync-cache)
    # Bidirectional union of the SHARED ccache dir with the instance.
    # ccache objects are content-addressed + immutable, so --size-only is a safe
    # union merge and --delete is NEVER used (no side ever loses cache).
    DNS=$(get_dns)
    LOCAL_CACHE="${EC2_CCACHE_DIR:-$HOME/.cache/ec2-ccache}"
    REMOTE_CACHE=".cache/ec2-ccache"   # relative to remote $HOME
    SSH_CMD="ssh -i $EC2_PEM -o StrictHostKeyChecking=no"
    mkdir -p "$LOCAL_CACHE"
    $SSH_CMD "${EC2_USER}@${DNS}" "mkdir -p ~/${REMOTE_CACHE}"
    # ccache objects are content-addressed + immutable and we merge with
    # --size-only, so times/owner/perms are cosmetic. Skip preserving them to
    # avoid "failed to set times ... Operation not permitted" on root-owned
    # files written by the docker build container.
    CACHE_RSYNC=(-rlz --size-only --no-owner --no-group --no-perms --omit-dir-times --no-times --progress)
    echo "Pull  ${EC2_USER}@${DNS}:~/${REMOTE_CACHE} -> ${LOCAL_CACHE}"
    rsync "${CACHE_RSYNC[@]}" \
      -e "$SSH_CMD" \
      "${EC2_USER}@${DNS}:${REMOTE_CACHE}/" "$LOCAL_CACHE/"
    echo "Push  ${LOCAL_CACHE} -> ${EC2_USER}@${DNS}:~/${REMOTE_CACHE}"
    rsync "${CACHE_RSYNC[@]}" \
      -e "$SSH_CMD" \
      "$LOCAL_CACHE/" "${EC2_USER}@${DNS}:${REMOTE_CACHE}/"
    echo "ccache sync complete (union merge, no deletions)."
    ;;

  port_forward)
    PORT_MAP="${EXTRA_ARG:-}"
    if [[ "$PORT_MAP" == "stop" ]]; then
      DNS=$(get_dns)
      PIDS=$(pgrep -f "ssh.*-N.*-f.*-L.*${DNS}" || true)
      if [[ -z "$PIDS" ]]; then
        echo "No SSH port forwarding processes found for ${DNS}."
      else
        echo "$PIDS" | xargs kill
        echo "Stopped SSH port forwarding to ${DNS}."
      fi
      exit 0
    fi
    if [[ -z "$PORT_MAP" ]]; then
      echo "Usage: $0 port_forward <local:remote>"
      echo "       $0 port_forward stop"
      exit 1
    fi
    if [[ -z "$EC2_PEM" ]]; then
      echo "Error: no PEM file provided. Set \$EC2_PEM_FILE or pass --pem <file>"
      exit 1
    fi
    LOCAL_PORT="${PORT_MAP%%:*}"
    REMOTE_PORT="${PORT_MAP##*:}"
    DNS=$(get_dns)
    echo "Forwarding localhost:${LOCAL_PORT} -> ${DNS}:${REMOTE_PORT}"
    ssh -i "$EC2_PEM" -o StrictHostKeyChecking=no -N -f -L "${LOCAL_PORT}:localhost:${REMOTE_PORT}" "${EC2_USER}@${DNS}"
    ;;

  status)
    STATE=$(get_status)
    echo "Instance $INSTANCE_LABEL is: $STATE"
    ;;

  start)
    STATE=$(get_status)
    if [[ "$STATE" == "running" ]]; then
      echo "Instance $INSTANCE_LABEL is already running."
      exit 0
    fi
    echo "Starting $INSTANCE_LABEL..."
    aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --output text > /dev/null
    echo -n "Waiting for running state"
    while [[ "$(get_status)" != "running" ]]; do
      echo -n "."; sleep 3
    done
    echo -e "\nInstance $INSTANCE_LABEL is now running."
    ;;

  start-workflow)
    # 1. Start instance if not already running
    STATE=$(get_status)
    if [[ "$STATE" != "running" ]]; then
      echo "Starting $INSTANCE_LABEL..."
      aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --output text >/dev/null
      echo -n "Waiting for running state"
      while [[ "$(get_status)" != "running" ]]; do
        echo -n "."; sleep 3
      done
      echo -e "\nInstance $INSTANCE_LABEL is now running."
      echo "Waiting 5s for SSH to become available..."
      sleep 5
    else
      echo "Instance $INSTANCE_LABEL is already running."
    fi

    DNS=$(get_dns)
    SCRIPT_ARGS=("$INSTANCE_ID" --region "$REGION" --pem "$EC2_PEM" --user "$EC2_USER")

    # 2. Port forward 8080
    echo "Forwarding localhost:8080 -> ${DNS}:8080"
    ssh -i "$EC2_PEM" -o StrictHostKeyChecking=no -N -f -L "8080:localhost:8080" "${EC2_USER}@${DNS}"

    # 3. Start watch-sync in background, log to file
    SYNC_LOG="/tmp/ec2-sync-${INSTANCE_ID}.log"
    SYNC_PID=""
    WATCHDOG_PID=""
    if command -v inotifywait &>/dev/null; then
      "$0" sync --watch "${SCRIPT_ARGS[@]}" >"$SYNC_LOG" 2>&1 &
      SYNC_PID=$!
      echo "File watcher started (PID $SYNC_PID) — logs at $SYNC_LOG"
      # Watchdog: if the watcher dies unexpectedly, alert loudly. cleanup()
      # kills this BEFORE killing SYNC_PID, so normal exit fires no false alarm.
      ( while kill -0 "$SYNC_PID" 2>/dev/null; do sleep 5; done
        command -v notify-send &>/dev/null && \
          notify-send -u critical "ec2.sh" "File sync watcher DIED — edits no longer syncing (log: $SYNC_LOG)" 2>/dev/null || true
        printf '\a\n\033[1;31m[ec2.sh] ⚠ Sync watcher DIED (PID %s) — edits are NOT syncing. See %s\033[0m\n' "$SYNC_PID" "$SYNC_LOG" >/dev/tty 2>/dev/null || true
      ) &
      WATCHDOG_PID=$!
    else
      echo "Warning: inotifywait not found — skipping file watch (install inotify-tools)"
    fi

    # Cleanup on exit: kill watcher + port forward, but leave instance running
    cleanup() {
      [[ -n "$WATCHDOG_PID" ]] && kill "$WATCHDOG_PID" 2>/dev/null || true
      [[ -n "$SYNC_PID" ]] && kill "$SYNC_PID" 2>/dev/null || true
      PIDS=$(pgrep -f "ssh.*-N.*-f.*-L.*8080:localhost:8080.*${DNS}" 2>/dev/null || true)
      [[ -n "$PIDS" ]] && echo "$PIDS" | xargs kill && echo "Port forward stopped."
      echo ""
      echo "⚠  Instance $INSTANCE_LABEL is still running — stop it with: ec2.sh stop"
    }
    trap cleanup EXIT INT TERM

    # 4. SSH in
    echo "SSHing into ${DNS}..."
    ssh -i "$EC2_PEM" -o StrictHostKeyChecking=no "${EC2_USER}@${DNS}"
    ;;

  scp)
    SCP_SRC="${EXTRA_ARG:-}"
    SCP_DST="${EXTRA_ARG2:-}"
    if [[ -z "$SCP_SRC" || -z "$SCP_DST" ]]; then
      echo "Usage: ec2.sh scp <src> <dst>"
      echo "  Prefix remote paths with ':' (e.g., :/home/ubuntu/file or :~/file)"
      exit 1
    fi
    DNS=$(get_dns)
    resolve_scp_path() {
      local p="$1"
      if [[ "$p" == :* ]]; then
        echo "${EC2_USER}@${DNS}${p}"
      else
        echo "$p"
      fi
    }
    SCP_FLAGS=(-i "$EC2_PEM" -o StrictHostKeyChecking=no)
    [[ -n "$RECURSIVE" ]] && SCP_FLAGS+=(-r)
    RESOLVED_SRC=$(resolve_scp_path "$SCP_SRC")
    RESOLVED_DST=$(resolve_scp_path "$SCP_DST")
    echo "scp ${RESOLVED_SRC} -> ${RESOLVED_DST}"
    scp "${SCP_FLAGS[@]}" "$RESOLVED_SRC" "$RESOLVED_DST"
    ;;

  rsync)
    RSYNC_SRC="${EXTRA_ARG:-}"
    RSYNC_DST="${EXTRA_ARG2:-}"
    if [[ -z "$RSYNC_SRC" || -z "$RSYNC_DST" ]]; then
      echo "Usage: ec2.sh rsync <src> <dst>"
      echo "  Prefix remote paths with ':' (e.g., :/home/ubuntu/file or :~/path)"
      exit 1
    fi
    DNS=$(get_dns)
    resolve_rsync_path() {
      local p="$1"
      if [[ "$p" == :* ]]; then
        echo "${EC2_USER}@${DNS}:${p#:}"
      else
        echo "$p"
      fi
    }
    RESOLVED_SRC=$(resolve_rsync_path "$RSYNC_SRC")
    RESOLVED_DST=$(resolve_rsync_path "$RSYNC_DST")
    echo "rsync ${RESOLVED_SRC} -> ${RESOLVED_DST}"
    rsync -azh --partial --progress \
      -e "ssh -i $EC2_PEM -o StrictHostKeyChecking=no" \
      "$RESOLVED_SRC" "$RESOLVED_DST"
    ;;

  stop)
    STATE=$(get_status)
    if [[ "$STATE" == "stopped" ]]; then
      echo "Instance $INSTANCE_LABEL is already stopped."
      exit 0
    fi
    echo "Stopping $INSTANCE_LABEL..."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --output text > /dev/null
    echo -n "Waiting for stopped state"
    while [[ "$(get_status)" != "stopped" ]]; do
      echo -n "."; sleep 3
    done
    echo -e "\nInstance $INSTANCE_LABEL is now stopped."
    ;;
esac
