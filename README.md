# red-horse — Tmux Session Launcher

Launch a pre-configured tmux session for development workflows with one command.

## Prerequisites

- **tmux** ≥ 3.0
- **jq** (for config parsing)
- **zsh** or **bash**
- **mise** (runtime manager for Node.js and pi)
- **Node.js** ≥ 22 (managed by mise)
- **pi** (AI coding assistant, managed by mise)

Install missing dependencies:

```bash
brew install tmux jq mise
mise install
```

## Quick Start

### 1. Create a default config

```bash
rh --init
```

This creates `~/.config/red-horse/config.json` with example windows commented out. Uncomment and edit them before launching.

### 2. Launch

```bash
rh
```

This creates a tmux session named `rh` with the configured windows, then attaches to it.

### 3. Customize

Edit `~/.config/red-horse/config.json`:

```json
{
  "session": "rh",
  "windows": [
    { "dir": "~/projects/my-project", "command": "nvim" },
    { "dir": "~/projects/other-project" }
  ]
}
```

Each window entry:

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `dir` | Yes | — | Working directory for the window |
| `command` | No | `nvim` | Command to run when the window opens |
| `name` | No | Slugified `dir` basename | Tmux window name |
| `skip_command` | No | `false` | If `true`, navigates to `dir` but doesn't run any command |
| `activate_on_start` | No | `false` | If `true`, this window is activated after creation (only the first `activate_on_start: true` window is selected) |

### 4. Re-launch / Re-attach

Running `rh` again while the session exists will simply attach to it:

```bash
rh  # attaches to existing session
```

## Usage

```
rh                    Create session and attach
rh --no-attach        Create session without attaching
rh --help             Show help
rh --init             Create default config
rh --destroy          Kill the red-horse session
```

## Alias Setup

Add this to your `~/.zshrc` (or `~/.bashrc`):

### Option A: Alias to local script (simplest)

```bash
alias rh='bash ~/projects/red-horse/rh.sh'
```

### Option B: Put red-horse in PATH

```bash
# Add the directory to PATH
export PATH="$HOME/projects/red-horse:$PATH"
```

Then `rh` works from any directory without the full path.

After adding, reload your shell:

```bash
source ~/.zshrc   # or ~/.bashrc
```

## Config Reference

Full config file at `~/.config/red-horse/config.json`:

```json
{
  "session": "rh",
  "windows": [
    { "dir": "~/projects/my-project", "command": "nvim" },
    { "dir": "~/projects/logs" }
  ]
}
```

- **`session`** — tmux session name (default: `rh`)
- **`windows`** — array of window definitions (required; no defaults)

## Non-Goals

- Multiple named sessions / profiles — single session model only
- Pane layout customization — one pane per window
- Persistence beyond tmux's built-in session management
- Cross-platform support (macOS + Linux, tmux + zsh/bash)

## Troubleshooting

### "Config not found"

Run `rh --init` to create the default config.

### "jq is required but not installed"

```bash
brew install jq
```

### Session already exists

`rh` will auto-attach. To recreate, destroy first:

```bash
rh --destroy
rh
```

### Window directory doesn't exist

red-horse skips that window and warns. Update your config to point to valid directories.
