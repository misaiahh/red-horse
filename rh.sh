#!/usr/bin/env bash
#
# red-horse — Launch a configurable tmux session for development workflows.
#
# Usage:
#   rh                    Create session and attach
#   rh --no-attach        Create session without attaching
#   rh --pi               Launch pi with the project's node version
#   rh --help             Show help
#   rh --init             Create default config at ~/.config/red-horse/config.json
#   rh --destroy          Kill the red-horse session
#
# Config: ~/.config/red-horse/config.json
#
# If no windows are defined in config, defaults are used:
#   1. llama  → cd ~/projects/llama-pi && ./run-server.sh
#   2. pi     → mise exec node@$NODE_VERSION -- pi

set -euo pipefail

# ─── Constants ───────────────────────────────────────────────────────────────

SESSION_NAME="red-horse-session"
CONFIG_DIR="$HOME/.config/red-horse"
CONFIG_FILE="$CONFIG_DIR/config.json"

# ─── Helpers ─────────────────────────────────────────────────────────────────

die() {
  echo "Error: $*" >&2
  exit 1
}

warn() {
  echo "Warning: $*" >&2
}

info() {
  echo "$*"
}

usage() {
  cat <<EOF
red-horse — Launch a configurable tmux session for development workflows.

Usage:
  rh                    Create session and attach
  rh --no-attach        Create session without attaching
  rh --pi               Launch pi with the project's node version
  rh --help             Show this help
  rh --init             Create default config at ~/.config/red-horse/config.json
  rh --destroy          Kill the red-horse session

Config file: ~/.config/red-horse/config.json

If no windows are defined in config, defaults are used:
  1. llama  → cd ~/projects/llama-pi && ./run-server.sh
  2. pi     → mise exec node@$NODE_VERSION -- pi

To customize, create a config with a "windows" array:
  {
    "session": "red-horse-session",
    "windows": [
      { "dir": "~/projects/my-project", "command": "nvim" },
      { "dir": "~/projects/other", "command": "top" }
    ]
  }

Each window entry:
  dir      (required)   Working directory for the window
  command  (optional)   Command to run (defaults to "nvim")
  name     (optional)   Window name (defaults to slugified dir basename)
  skip_command  (optional)  If true, navigates to dir but doesn't run command
EOF
  exit 0
}

# Slugify: convert a string to a tmux-safe window name
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' /' '--' | sed 's/--*/-/g; s/^-//; s/-$//'
}

# Expand ~ in paths
expand_path() {
  local p="$1"
  if [[ "$p" == "~"* ]]; then
    p="${p/#\~/$HOME}"
  fi
  echo "$p"
}

# ─── Dependency checks ───────────────────────────────────────────────────────

check_deps() {
  command -v jq    >/dev/null 2>&1 || die "jq is required but not installed. Install with: brew install jq"
  command -v tmux  >/dev/null 2>&1 || die "tmux is required but not installed. Install with: brew install tmux"
}

# ─── Config helpers ──────────────────────────────────────────────────────────

config_exists() {
  [[ -f "$CONFIG_FILE" ]]
}

# Check if the windows array is non-empty
has_windows() {
  local count
  count=$(jq '.windows | if type == "array" then length else 0 end' "$CONFIG_FILE" 2>/dev/null || echo 0)
  [[ "$count" -gt 0 ]]
}

# ─── Node version check ──────────────────────────────────────────────────────

# Verify the required Node version is installed via mise
check_node_version() {
  command -v mise >/dev/null 2>&1 || die "mise is required but not installed. Install with: brew install mise"
  mise activate bash >/dev/null 2>&1 || true
  local installed
  installed=$(mise which node 2>/dev/null || true)
  if [[ -z "$installed" ]]; then
    die "Node $NODE_VERSION is not installed via mise. Install it with: mise install node@$NODE_VERSION"
  fi
  local actual_version
  actual_version=$($installed --version 2>/dev/null | sed 's/v//')
  if [[ "$actual_version" != "$NODE_VERSION" ]]; then
    die "Expected Node $NODE_VERSION but found $actual_version. Install the correct version with: mise install node@$NODE_VERSION"
  fi
}

# ─── Default windows ─────────────────────────────────────────────────────────

# Returns JSON array of default windows
get_default_windows() {
  cat <<EOF
[
  {
    "dir": "~/projects/llama-pi",
    "skip_command": true,
    "name": "llama"
  },
  {
    "dir": "~/projects/red-horse",
    "command": "mise exec node@$NODE_VERSION -- pi",
    "name": "pi"
  }
]
EOF
}

# ─── --init ──────────────────────────────────────────────────────────────────

cmd_init() {
  if config_exists; then
    die "Config already exists at $CONFIG_FILE. Remove it first to overwrite."
  fi

  mkdir -p "$CONFIG_DIR"

  cat > "$CONFIG_FILE" <<'EOF'
{
  "session": "red-horse-session",
  "windows": []
}
EOF

  info "Default config created at $CONFIG_FILE"
  info "Run 'rh' to launch with default windows (llama + pi)."
  info "Edit $CONFIG_FILE to customize."
}

# ─── --destroy ───────────────────────────────────────────────────────────────

cmd_destroy() {
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux kill-session -t "$SESSION_NAME"
    info "Session '$SESSION_NAME' killed."
  else
    info "No session '$SESSION_NAME' found."
  fi
}

# ─── --help ──────────────────────────────────────────────────────────────────

cmd_help() {
  usage
}

# ─── --pi ────────────────────────────────────────────────────────────────────

# Node version used by the default pi window
NODE_VERSION="22.19.0"

cmd_pi() {
  check_node_version
  info "Launching pi with node@$NODE_VERSION via mise..."
  mise exec node@$NODE_VERSION -- pi
}

# ─── Main session creation ───────────────────────────────────────────────────

cmd_launch() {
  local no_attach=false

  if [[ "${1:-}" == "--no-attach" ]]; then
    no_attach=true
  fi

  # Check Node version
  check_node_version

  # Check config
  if ! config_exists; then
    die "Config not found at $CONFIG_FILE. Run 'rh --init' to create it."
  fi

  # Validate JSON
  if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    die "Config at $CONFIG_FILE is not valid JSON."
  fi

  # Determine window source
  local windows_json
  if has_windows; then
    windows_json=$(jq '.windows' "$CONFIG_FILE")
  else
    windows_json=$(get_default_windows)
  fi

  # Count windows
  local window_count
  window_count=$(echo "$windows_json" | jq 'length')

  if [[ "$window_count" -eq 0 ]]; then
    die "No windows defined in config and no defaults available."
  fi

  # Check if session already exists
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    if [[ "$no_attach" == true ]]; then
      info "Session '$SESSION_NAME' already exists. Using --no-attach, exiting."
    else
      info "Session '$SESSION_NAME' already exists. Attaching..."
      tmux attach-session -t "$SESSION_NAME"
      exit 0
    fi
  fi

  # Create detached session (first window)
  info "Creating session '$SESSION_NAME' with $window_count window(s)..."

  # Parse and create each window
  local first=true
  for (( i=0; i<window_count; i++ )); do
    local dir command name skip_cmd

    dir=$(echo "$windows_json" | jq -r ".[$i].dir")
    command=$(echo "$windows_json" | jq -r ".[$i].command // \"nvim\"")
    name=$(echo "$windows_json" | jq -r ".[$i].name // empty")
    skip_cmd=$(echo "$windows_json" | jq -r ".[$i].skip_command // false")

    # Expand ~ in dir
    dir=$(expand_path "$dir")

    # Derive name from dir if not provided
    if [[ -z "$name" ]]; then
      local basename_dir
      basename_dir=$(basename "$dir")
      name=$(slugify "$basename_dir")
    fi

    # Check directory exists
    if [[ ! -d "$dir" ]]; then
      warn "Directory '$dir' does not exist. Skipping window '$name'."
      continue
    fi

    if [[ "$first" == true ]]; then
      # Create first window (this becomes the session)
      tmux new-session -d -s "$SESSION_NAME" -n "$name" -c "$dir"
      first=false
    else
      # Create additional windows
      tmux new-window -t "$SESSION_NAME" -n "$name" -c "$dir"
    fi

    # Send command to the window (unless skip_command is true)
    if [[ "$skip_cmd" != "true" ]]; then
      tmux send-keys -t "$SESSION_NAME:$name" "$command" Enter
    fi

    info "  Window '$name': dir=$dir cmd=$command"
  done

  # Attach
  if [[ "$no_attach" == false ]]; then
    tmux attach-session -t "$SESSION_NAME"
  else
    info "Session '$SESSION_NAME' created. (use 'tmux attach -t $SESSION_NAME' to attach)"
  fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
  local cmd="${1:-launch}"

  case "$cmd" in
    --help|-h)
      cmd_help
      ;;
    --init)
      cmd_init
      ;;
    --destroy)
      cmd_destroy
      ;;
    --no-attach)
      check_deps
      cmd_launch --no-attach
      ;;
    --pi)
      cmd_pi
      ;;
    launch)
      check_deps
      cmd_launch
      ;;
    *)
      die "Unknown command: $cmd. Run 'rh --help' for usage."
      ;;
  esac
}

main "$@"
