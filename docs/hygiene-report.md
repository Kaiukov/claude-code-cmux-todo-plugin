# Repo Hygiene Report

**Date:** 2026-06-12  
**Branch:** `chore/repo-hygiene`  
**Scope:** Shell-script audit (shebang, `set -euo pipefail`, exec bit), safe fixes, plugin validation

---

## Tracked `*.sh` Audit

All 32 tracked `.sh` scripts were audited against three criteria:

| # | File | Shebang (`#!/usr/bin/env bash`) | `set -euo pipefail` | Executable |
|---|------|-------------------------------|---------------------|------------|
| 1 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/agent-audit.sh` | yes | yes | yes |
| 2 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/agent-kill.sh` | yes | yes | yes |
| 3 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/agent-notify.sh` | yes | yes | **no → fixed** |
| 4 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/agent-screen.sh` | yes | yes | yes |
| 5 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/agent-send.sh` | yes | yes | yes |
| 6 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/agent-spawn.sh` | yes | yes | yes |
| 7 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/lib.sh` | yes | yes | yes |
| 8 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/poll-push.sh` | yes | yes | yes |
| 9 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/poll-wait.sh` | yes | yes | yes |
| 10 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/pr-finish.sh` | yes | yes | yes |
| 11 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/verify-ts.sh` | yes | yes | yes |
| 12 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/verify.sh` | yes | yes | yes |
| 13 | `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/wt-new.sh` | yes | yes | yes |
| 14 | `plugins/cmux-todo-board/tests/test_agent_audit.sh` | yes | yes | **no → fixed** |
| 15 | `plugins/cmux-todo-board/tests/test_agent_notify.sh` | yes | yes | **no → fixed** |
| 16 | `plugins/cmux-todo-board/tests/test_agent_readiness_probe.sh` | yes | yes | yes |
| 17 | `plugins/cmux-todo-board/tests/test_agent_spawn_race.sh` | yes | yes | **no → fixed** |
| 18 | `plugins/cmux-todo-board/tests/test_board_add.sh` | yes | yes | **no → fixed** |
| 19 | `plugins/cmux-todo-board/tests/test_board_config.sh` | yes | yes | **no → fixed** |
| 20 | `plugins/cmux-todo-board/tests/test_board_model.sh` | yes | yes | **no → fixed** |
| 21 | `plugins/cmux-todo-board/tests/test_board_next.sh` | yes | yes | **no → fixed** |
| 22 | `plugins/cmux-todo-board/tests/test_board_onboard_lite.sh` | yes | yes | yes |
| 23 | `plugins/cmux-todo-board/tests/test_board_plan_cap.sh` | yes | yes | **no → fixed** |
| 24 | `plugins/cmux-todo-board/tests/test_board_pull_body.sh` | yes | yes | **no → fixed** |
| 25 | `plugins/cmux-todo-board/tests/test_board_pull_union.sh` | yes | yes | yes |
| 26 | `plugins/cmux-todo-board/tests/test_board_release.sh` | yes | yes | **no → fixed** |
| 27 | `plugins/cmux-todo-board/tests/test_board_render_body.sh` | yes | yes | **no → fixed** |
| 28 | `plugins/cmux-todo-board/tests/test_board_render.sh` | yes | yes | yes |
| 29 | `plugins/cmux-todo-board/tests/test_board_status.sh` | yes | yes | **no → fixed** |
| 30 | `plugins/cmux-todo-board/tests/test_board_sync.sh` | yes | yes | yes |
| 31 | `plugins/cmux-todo-board/tests/test_limit_monitor.sh` | yes | yes | **no → fixed** |
| 32 | `plugins/cmux-todo-board/tests/test_opencode_bin_resolve.sh` | yes | yes | **no → fixed** |
| 33 | `plugins/cmux-todo-board/tests/test_poll_wait.sh` | yes | yes | **no → fixed** |

**Summary:**
- **Shebang (`#!/usr/bin/env bash`):** 33/33 — all present
- **`set -euo pipefail`:** 33/33 — all present
- **Executable (100755):** 17/33 — 16 scripts were missing the exec bit and were fixed

---

## Fixes Applied

### Exec-bit additions (16 files)

Scripts that had a proper `#!/usr/bin/env bash` shebang but were not executable had the exec bit added:

1. `plugins/cmux-todo-board/skills/cmux-agent-workflows/scripts/agent-notify.sh`
2. `plugins/cmux-todo-board/tests/test_agent_audit.sh`
3. `plugins/cmux-todo-board/tests/test_agent_notify.sh`
4. `plugins/cmux-todo-board/tests/test_agent_spawn_race.sh`
5. `plugins/cmux-todo-board/tests/test_board_add.sh`
6. `plugins/cmux-todo-board/tests/test_board_config.sh`
7. `plugins/cmux-todo-board/tests/test_board_model.sh`
8. `plugins/cmux-todo-board/tests/test_board_next.sh`
9. `plugins/cmux-todo-board/tests/test_board_plan_cap.sh`
10. `plugins/cmux-todo-board/tests/test_board_pull_body.sh`
11. `plugins/cmux-todo-board/tests/test_board_release.sh`
12. `plugins/cmux-todo-board/tests/test_board_render_body.sh`
13. `plugins/cmux-todo-board/tests/test_board_status.sh`
14. `plugins/cmux-todo-board/tests/test_limit_monitor.sh`
15. `plugins/cmux-todo-board/tests/test_opencode_bin_resolve.sh`
16. `plugins/cmux-todo-board/tests/test_poll_wait.sh`

### Final-newline additions

**None needed.** All tracked `.sh` and `.md` files already ended with a trailing newline.

### No changes to script logic

All fixes were limited to file mode bits and a CHANGELOG.md entry. No script logic, refactoring, or content changes were made.

---

## Plugin Validation

```
claude plugin validate plugins/cmux-todo-board
```

**Result:** ✔ Validation passed

No structural or configuration issues detected in the plugin manifest.

---

## Files Modified

| File | Change |
|------|--------|
| `CHANGELOG.md` | Added `### Changed` entry under `[Unreleased]` |
| 16 `*.sh` files | Exec bit added (`chmod +x` + `git update-index --chmod=+x`) |
| `docs/hygiene-report.md` | This report (new file) |
