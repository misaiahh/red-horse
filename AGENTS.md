# red-horse — Agent Reference

Single-file bash project. Everything lives in `rh.sh`; `rh` is a thin wrapper that `exec`s `rh.sh` with the same args. No dependencies beyond bash builtins + `jq` + `tmux`.

## File Map

| File | Role |
|------|------|
| `rh.sh` | **Everything.** All logic, config parsing, tmux orchestration, help text, init template. |
| `rh` | Wrapper: `exec "$SCRIPT_DIR/rh.sh" "$@"` — lets the file sit in PATH. |
| `config.example.json` | Sample config for the repo (not installed by `--init`). |
| `README.md` | User-facing docs. Keep in sync with `rh.sh` usage/help and window fields. |
| `mise.toml` | Dev tooling: `node = "22.19"`, `pi = "latest"`. |

## Config

- **Path:** `~/.config/red-horse/config.json`
- **Session name:** `red-horse-session` (hardcoded constant `SESSION_NAME`)
- **JSON comments supported:** `//` comments are stripped via `sed` before `jq` parses. This is intentional — the init template uses `//` comments for examples.
- **Windows fallback:** If `.windows` is absent, empty, or not an array → uses `get_default_windows()` (llama + pi). If `.windows` exists with ≥1 entry → uses ONLY those (no fallback).
- **Directory validation:** Windows with non-existent `dir` are skipped with a warning.

## Window Fields

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `dir` | string (required) | — | Working directory. `~` is expanded to `$HOME`. |
| `command` | string | `"nvim"` | Sent via `tmux send-keys`. |
| `name` | string | slugified `dir` basename | Lowercase, spaces/slashes → `-`, collapsed. |
| `skip_command` | boolean | `false` | Skips `tmux send-keys` for this window. |
| `active` | boolean | `false` | First `active: true` window is selected via `tmux select-window` after all windows are created. If none, falls back to last created window. |

## Commands

| Command | Action |
|---------|--------|
| `rh` | Check deps → validate config → create session with windows → select active window → attach |
| `rh --no-attach` | Same as above but skip `tmux attach-session` |
| `rh --pi` | Check node ≥ 22.19.0 + pi installed → exec `pi` via mise |
| `rh --init` | Create `~/.config/red-horse/config.json` with commented-out examples (idempotent) |
| `rh --destroy` | `tmux kill-session -t red-horse-session` |
| `rh --help` / `-h` | Print usage from `usage()` heredoc |

## Launch Flow (cmd_launch)

1. Check `mise` + `node ≥ 22.19.0` + `pi installed`
2. Validate config exists + valid JSON
3. Determine window source: config `.windows` or defaults
4. If session already exists → attach and exit (unless `--no-attach`)
5. Create first window with `tmux new-session -d -s red-horse-session -n <name> -c <dir>`
6. Create remaining windows with `tmux new-window -t red-horse-session -n <name> -c <dir>`
7. Send command to each window (unless `skip_command: true`)
8. `tmux select-window -t red-horse-session:<active_name_or_last>`
9. `tmux attach-session -t red-horse-session`

## Key Constants

```bash
SESSION_NAME="red-horse-session"
CONFIG_DIR="$HOME/.config/red-horse"
CONFIG_FILE="$CONFIG_DIR/config.json"
NODE_VERSION="22.19.0"
```

## Helper Functions

- `die()` — print error to stderr, exit 1
- `warn()` — print warning to stderr
- `info()` — print to stdout
- `slugify()` — `tr` + `sed` pipeline for tmux-safe names
- `expand_path()` — expands `~` to `$HOME`
- `strip_comments()` — `sed 's|//.*||g'`
- `read_config_json()` — `cat config | strip_comments`
- `has_windows()` — jq check if `.windows` is a non-empty array
- `check_deps()` — verify `jq` and `tmux` in PATH
- `check_node_version()` — verify mise + node ≥ NODE_VERSION
- `check_pi()` — verify `mise exec node@$NODE_VERSION -- which pi` succeeds

## Default Windows

```json
[
  { "dir": "~/projects/llama-pi", "skip_command": true, "name": "llama" },
  { "dir": "~/projects/red-horse", "command": "pi", "name": "pi", "active": true }
]
```

## Common Patterns / Pitfalls

- **JSON comments:** Config files use `//` comments. Always pipe through `strip_comments` before `jq`. Never use `jq` directly on raw config.
- **`has_windows` logic:** Empty array `[]` → uses defaults. Non-empty → uses config only. This is the fallback boundary.
- **`active` semantics:** Only the FIRST `active: true` window is selected. Subsequent `active: true` entries are ignored. Falls back to last created window if none are active.
- **`--no-attach` on existing session:** Exits immediately (doesn't re-create). All other existing-session cases attach.
- **Directory check:** Windows with missing `dir` are skipped mid-loop. `last_name` and `active_name` are only updated for successfully created windows.
- **`set -euo pipefail`:** Script fails on any error. Use `|| true` or `|| die "..."` to handle expected failures.

## History of Changes

| Commit | Change |
|--------|--------|
| `b40a085` | Fixed node/pi version resolution issues (mise exec workaround) |
| `6cc55ba` | Added JSON comment support, improved pi window reliability |
| `2bb60c2` | Added pi installation check |
| `f652c80` | Added node version check |
| `b9959f6` | Fixed node version and relative paths |
| `3f207f1` | Fixed `rh` alias |
| `2fc9b67` | Initial commit |

## TODO / Known Gaps

- `session` field in config is parsed but **not used** — session name is hardcoded to `red-horse-session`
- No pane support — one pane per window only
- No named sessions (profiles) — single session model
- Config is per-user (`~/.config/`), not per-project
