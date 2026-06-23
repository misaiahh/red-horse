# red-horse — Tmux Session Launcher

Launch a pre-configured tmux session for development workflows with one command.

## Prerequisites

- **tmux** ≥ 3.0
- **jq** (for config parsing)
- **zsh** or **bash**

Install missing dependencies:

```bash
brew install tmux jq
```

## Quick Start

### 1. Create a default config

```bash
rh --init
```

This creates `~/.config/red-horse/config.json` with an empty window list. With no windows defined, red-horse falls back to two default windows:

| Window | Command | Directory |
|--------|---------|-----------|
| `llama` | `./run-server.sh` | `~/SideProjects/llama-pi` |
| `pi` | `mise exec -- node@22.15.0 -- pi` | `~/SideProjects/red-horse` |

### 2. Launch

```bash
rh
```

This creates a tmux session named `red-horse-session` with the configured (or default) windows, then attaches to it.

### 3. Customize

Edit `~/.config/red-horse/config.json`:

```json
{
  "session": "red-horse-session",
  "windows": [
    { "dir": "~/SideProjects/llama-pi", "skip_command": true, "name": "llama" },
    { "dir": "~/SideProjects/red-horse", "command": "mise exec -- node@22.15.0 -- pi", "name": "pi" },
    { "dir": "~/SideProjects/my-project", "command": "nvim" },
    { "dir": "~/SideProjects/other-project" }
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
alias rh='bash ~/SideProjects/red-horse/red-horse.sh'
```

### Option B: Put red-horse in PATH

```bash
# Add the directory to PATH
export PATH="$HOME/SideProjects/red-horse:$PATH"
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
  "session": "red-horse-session",
  "windows": [
    { "dir": "~/SideProjects/llama-pi", "skip_command": true, "name": "llama" },
    { "dir": "~/SideProjects/my-project", "command": "nvim" },
    { "dir": "~/SideProjects/logs" }
  ]
}
```

- **`session`** — tmux session name (default: `red-horse-session`)
- **`windows`** — array of window definitions
  - If empty or omitted, defaults to `llama` + `pi` windows
  - If present (even with one entry), uses only the defined windows

## Default Windows

When no windows are defined in config, these two are used:

| Window | Command | Directory |
|--------|---------|-----------|
| `llama` | `cd ~/SideProjects/llama-pi && ./run-server.sh` | `~/SideProjects/llama-pi` |
| `pi` | `cd ~/SideProjects/red-horse && mise exec -- node@22.15.0 -- pi` | `~/SideProjects/red-horse` |

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
