# board-install — deploy script for cmux-todo-board

`board-install` installs or updates the cmux-todo-board plugin into the
correct config directory for each supported host (Claude Code, OpenCode, Codex).
It reads the current version from the plugin manifest so it always deploys the
latest without hardcoded versions.

## Quick start

```bash
# Install/update into all supported hosts
bash plugins/cmux-todo-board/bin/board-install

# Preview without writing anything
bash plugins/cmux-todo-board/bin/board-install --dry-run

# Check version status across all hosts
bash plugins/cmux-todo-board/bin/board-install --check
```

## Usage

```
board-install [--target <claude|opencode|codex|all>] [--dry-run] [--check]
board-install --help
```

### Targets

| Target      | Config directory                                         | Override env       |
|-------------|----------------------------------------------------------|--------------------|
| `claude`    | `~/.claude/plugins/cmux-todo-board/`                     | —                  |
| `opencode`  | `~/.config/opencode/`                                    | —                  |
| `codex`     | `~/.codex/`                                              | `CODEX_CONFIG_HOME` |
| `all`       | All of the above (default)                               | —                  |

The default target is `all`.

### Mode flags

| Flag          | Description                                                                 |
|---------------|-----------------------------------------------------------------------------|
| `--dry-run`   | Print what WOULD be copied or linked; write nothing; exit 0.                |
| `--check`     | Compare installed plugin version against the repo's current version.        |
|               | Reports `up-to-date` / `outdated` / `not-installed` per target; no writes.  |
| `--help`      | Print usage and exit.                                                       |

### Version detection

The script reads the current version from the authoritative plugin manifest at
`plugins/cmux-todo-board/.claude-plugin/plugin.json` (the `version` field). No
version string is ever hardcoded in the script — it always reads the manifest
at runtime.

### Symlink coexistence (#81 / #83 wiring)

If a target path or any of its sub-paths is a symlink (e.g. OpenCode config
symlinked back to a repo checkout), `board-install` detects it, reports the
symlink target, and skips that path. This preserves the global symlink wiring
from #81/#83 and prevents accidental clobbering. The check runs on real
installs; `--dry-run` always skips writing.

### Idempotency

Re-running `board-install` makes no spurious changes. If files already exist
and match the repo, they are overwritten with identical content (a no-op in
effect). The version string in logs reflects the currently deployed version.

## Per-target details

### claude

Installs the full plugin directory (`plugins/cmux-todo-board/`) into
`~/.claude/plugins/cmux-todo-board/`, excluding `tests/`. This includes:

- `.claude-plugin/plugin.json` — plugin manifest
- `.codex-plugin/` — Codex adapter (available for cross-reference)
- `.opencode/` — OpenCode adapter (available for cross-reference)
- `bin/` — board commands
- `skills/` — skill definitions
- `hooks/` — session hooks
- `docs/` — documentation
- `prompts/` — prompt assets

### opencode

Installs the `.opencode/` contents (`opencode.json`, `package.json`,
`plugins/cmux-board.mjs`, `agent/orchestrator.md`) plus `bin/` and `skills/`
into `~/.config/opencode/`. This makes the OpenCode plugin tools
(`board_status`, `board_next`, `board_sync`) and the orchestrator agent
available globally.

### codex

Installs the `.codex-plugin/` contents (`plugin.json`) into `~/.codex/`
(or `$CODEX_CONFIG_HOME`). Assumes Codex stores plugins under
`~/.codex/plugin.json`. If your Codex install uses a different path, set:

```bash
CODEX_CONFIG_HOME=/path/to/codex/config board-install --target codex
```

## Examples

```bash
# Install only the Claude plugin
board-install --target claude

# Preview what would be installed for OpenCode
board-install --target opencode --dry-run

# Check if the installed Codex plugin is up to date
board-install --target codex --check

# Check all targets (no writes)
board-install --check

# Install with a custom Codex path
CODEX_CONFIG_HOME=~/.config/codex board-install --target codex

# Full install to all targets with preview first
board-install --dry-run
board-install
```

## Verification

```bash
# Syntax check
bash -n plugins/cmux-todo-board/bin/board-install

# Run tests
bash plugins/cmux-todo-board/tests/test_board_install.sh
```
