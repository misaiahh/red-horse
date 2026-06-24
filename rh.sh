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
#   2. pi     → pi (uses mise-managed Node ≥ $NODE_VERSION)

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

If no windows are defined in config (or all are commented out), defaults are used:
  1. llama  → cd ~/projects/llama-pi && ./run-server.sh
  2. pi     → pi (uses mise-managed Node ≥ $NODE_VERSION)

To customize, uncomment and edit the example windows in the config:
  {
    // "windows": [
    //   { "dir": "~/projects/my-project", "command": "nvim" },
    //   { "dir": "~/projects/other", "command": "top" }
    // ]
  }

Each window entry:
  dir      (required)   Working directory for the window
  command  (optional)   Command to run (defaults to "nvim")
  name     (optional)   Window name (defaults to slugified dir basename)
  skip_command  (optional)  If true, navigates to dir but doesn't run command
  activate_on_start  (optional)   If true, this window is activated after creation (only the first activate_on_start: true window is selected)
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

# Strip JSON comments (// style) so jq can parse config files with examples
strip_comments() {
  sed 's|//.*||g'
}

# Read config file with comments stripped for jq parsing
read_config_json() {
  cat "$CONFIG_FILE" | strip_comments
}

# ─── Config helpers ──────────────────────────────────────────────────────────

# Config key aliases (hyphen → underscore)
_KEY_MAP='{"activate-on-start":"activate_on_start","skip-command":"skip_command"}'

# Normalize config: strip comments → alias kebab-case keys to snake_case →
# strip keys whose values don't match the expected type (so jq defaults kick in).
# Usage: normalize_config_json | jq '.windows'
normalize_config_json() {
  cat "$CONFIG_FILE" | strip_comments | jq --argjson KEY_MAP "$_KEY_MAP" '
    def normalize:
      if type == "object" then
        with_entries(
          .key as $orig |
          ($KEY_MAP[$orig] // .key) as $new_key |
          if $new_key == "skip_command" or $new_key == "activate_on_start" then
            if (.value | type) == "boolean" then
              {key: $new_key, value: .value}
            else empty end
          elif $new_key == "dir" or $new_key == "command" or $new_key == "name" then
            if (.value | type) == "string" then
              {key: $new_key, value: .value}
            else empty end
          else
            {key: $new_key, value: (.value | normalize)}
          end
        )
      else . end;
    walk(normalize)
  '
}

# ─── Dependency checks ───────────────────────────────────────────────────────

check_deps() {
  command -v jq    >/dev/null 2>&1 || die "jq is required but not installed. Install with: brew install jq"
  command -v tmux  >/dev/null 2>&1 || die "tmux is required but not installed. Install with: brew install tmux"
}

config_exists() {
  [[ -f "$CONFIG_FILE" ]]
}

# Check if the windows array is non-empty
has_windows() {
  local count
  count=$(normalize_config_json | jq '.windows | if type == "array" then length else 0 end' 2>/dev/null || echo 0)
  [[ "$count" -gt 0 ]]
}

# ─── Node version check ──────────────────────────────────────────────────────

# Verify the minimum Node version is installed via mise
check_node_version() {
  command -v mise >/dev/null 2>&1 || die "mise is required but not installed. Install with: brew install mise"
  local actual_version
  actual_version=$(node --version 2>/dev/null | sed 's/v//')
  if [[ -z "$actual_version" ]]; then
    die "Node.js is not installed or not in PATH. Install with: mise install node@$NODE_VERSION"
  fi
  # Check that actual_version >= NODE_VERSION (minimum version check)
  if [[ "$(printf '%s\n%s\n' "$NODE_VERSION" "$actual_version" | sort -V | head -n1)" != "$NODE_VERSION" ]]; then
    die "Node.js must be ≥ $NODE_VERSION (found $actual_version). Install with: mise install node@$NODE_VERSION"
  fi
}

# Verify pi is installed in the project's Node version
check_pi() {
  command -v mise >/dev/null 2>&1 || die "mise is required but not installed. Install with: brew install mise"
  local pi_path
  pi_path=$(mise exec node@$NODE_VERSION -- which pi 2>/dev/null || true)
  if [[ -z "$pi_path" ]]; then
    die "pi is not installed in node@$NODE_VERSION. Install it with: npm install -g @earendil-works/pi-coding-agent"
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
    "command": "pi",
    "name": "pi",
    "activate_on_start": true
  }
]
EOF
}

# ─── --init ──────────────────────────────────────────────────────────────────

cmd_init() {
  if config_exists; then
    return 0
  fi

  mkdir -p "$CONFIG_DIR"

  cat > "$CONFIG_FILE" <<'EOF'
{
  // Session name (optional, defaults to "red-horse-session")
  // "session": "red-horse-session",

  // Windows to create in the session
  // "windows": [
  //   {
  //     "dir": "~/projects/my-project",
  //     "command": "nvim",
  //     "name": "project"
  //   },
  //   {
  //     "dir": "~/projects/other",
  //     "command": "top",
  //     "skip_command": true
  //   },
  //   {
  //     "dir": "~/projects/important",
  //     "command": "nvim",
  //     "name": "important",
  //     "activate_on_start": true
  //   }
  // ]
}
EOF

  info "Config created at $CONFIG_FILE"
  info "Uncomment the example windows above to use them, or add your own."
  info "Then run 'rh' to launch the session."
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

# Minimum Node version required for pi
NODE_VERSION="22.19.0"

cmd_pi() {
  check_node_version
  check_pi
  info "Launching pi with node@$NODE_VERSION via mise..."
  pi
}

# ─── Main session creation ───────────────────────────────────────────────────

cmd_launch() {
  local no_attach=false

  if [[ "${1:-}" == "--no-attach" ]]; then
    no_attach=true
  fi

  # Check Node version and pi
  check_node_version
  check_pi

  # Check config
  if ! config_exists; then
    die "Config not found at $CONFIG_FILE. Run 'rh --init' to create it."
  fi

  # Validate JSON (strip // comments first — jq doesn't support them)
  if ! read_config_json | jq empty 2>/dev/null; then
    die "Config at $CONFIG_FILE is not valid JSON."
  fi

  # Determine window source
  local windows_json
  if has_windows; then
    windows_json=$(normalize_config_json | jq '.windows')
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
  local activate_on_start_idx=""
  local last_idx=""
  local tmux_idx=0
  for (( i=0; i<window_count; i++ )); do
    local dir command name skip_cmd activate_on_start

    dir=$(echo "$windows_json" | jq -r ".[$i].dir")
    command=$(echo "$windows_json" | jq -r ".[$i].command // \"nvim\"")
    name=$(echo "$windows_json" | jq -r ".[$i].name // empty")
    skip_cmd=$(echo "$windows_json" | jq -r ".[$i].skip_command // false")
    activate_on_start=$(echo "$windows_json" | jq -r ".[$i].activate_on_start // false")

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

    # Track last created window index and first activate_on_start window index (use actual tmux index)
    last_idx=$tmux_idx
    if [[ "$activate_on_start" == "true" && -z "$activate_on_start_idx" ]]; then
      activate_on_start_idx=$tmux_idx
    fi

    if [[ "$first" == true ]]; then
      # Create first window (this becomes the session)
      tmux new-session -d -s "$SESSION_NAME" -n "$name" -c "$dir"
      first=false
    else
      # Create additional windows
      tmux new-window -t "$SESSION_NAME" -n "$name" -c "$dir"
    fi

    tmux_idx=$((tmux_idx + 1))

    # Send command to the window (unless skip_command is true)
    if [[ "$skip_cmd" != "true" ]]; then
      tmux send-keys -t "$SESSION_NAME:$name" "$command" Enter
    fi

    info "  Window '$name': dir=$dir cmd=$command"
  done

  # Activate the first activate_on_start window (or fall back to last created)
  local target_idx="${activate_on_start_idx:-$last_idx}"
  if [[ -n "$target_idx" ]]; then
    tmux select-window -t "$SESSION_NAME:$target_idx"
  fi

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
