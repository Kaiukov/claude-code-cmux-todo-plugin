# Changelog

All notable changes to this project are documented here.
This project adheres to semantic versioning.

## [Unreleased]

### Added
- Damage-control safety gate for Pi workers: data-driven `.pi/damage-control-rules.yaml`
  deny/ask list + `damage-control.ts` Pi extension (ported from disler/pi-vs-claude-code,
  MIT), loaded for pi workers at spawn. `--force-with-lease` allowed; `--force` denied (#91).
- Pi role profiles (backend/frontend/frontend-top/review/docs): `board-config
  --get-profile <name>` resolves a profile to `{provider, model, thinking, tools}`
  and `agent-spawn.sh --profile <name>` launches a Pi worker from it. Profiles are
  configuration over the Pi runtime; tier/`--model`/`--agent` paths unchanged (#102).
- `pi` agent-kind: canonical Pi worker launch path (`agent-spawn.sh --agent pi`),
  with provider/model split, trust pre-seed, and ready/kill patterns. OpenCode and
  Codex paths kept as fallback (#90).
- Reusable maximally-detailed `.task-spec.md` template
  (`skills/cmux-agent-workflows/templates/task-spec.template.md`) with scope,
  exact file bounds, acceptance, verification, commit/push, contention-guard
  convention, and forbidden paths, plus a guide in docs/task-spec-template.md (L10).

### Fixed
- Completion-wait now filters the cmux event stream by worker cwd (no cross-wake
  between parallel workers) and tears down its event listener without leaking
  `cmux events` processes (#92).

## [0.6.0] - 2026-06-12

### Added
- docs: orchestrator token-efficiency diagnostics + benchmark + secret-safe rules (#107).
- docs: canonical orchestrator token-efficiency policy (budgets, routing, handoff, bounded specs) (#106).
- docs: Pi CLI usage guide + cmux terminal agent-spawn recipe (docs/pi-cli-usage.md)
- `pr-finish.sh` now requires explicit user confirmation before merge/close (L5).
- cmux notify/feed cheat sheet (docs/cmux-cheat-sheet.md) (#82)
- Install-location-independent `bin/` resolution in `.opencode/plugins/cmux-board.mjs`: priority-ordered lookup via `CMUX_BOARD_HOME` env var → walk-up search for `bin/board-status` → relative fallback (#81).

### Changed
- Orchestration skills: lite path is now the default; full skill is on-demand (#105).
- chore: repo hygiene pass (shell-script audit, trailing newlines, exec bits)
- `.opencode/agent/orchestrator.md` `mode: primary` agent encoding the orchestrator role, board workflow, delegation cycle, and standby rule (#81).
- Skills discoverability via `skills.paths` in `.opencode/opencode.json`, pointing at the existing `skills/` directory (#81).
- `tests/test_opencode_bin_resolve.sh` — 6 tests covering CMUX_BOARD_HOME override, walk-up discovery, fallback, and real repo resolution (#81).
- First-class OpenCode plugin entrypoint (`.opencode/`) exposing `board_status`, `board_next`, `board_sync` as native custom tools plus `shell.env` and `session.idle` hooks (#78).
- Default `model: opencode-go/deepseek-v4-pro` for the `.opencode/agent/orchestrator.md` agent so it no longer falls back to an unconfigured local provider (#81).
- `board-model` — project-level provider/model registry and tier assignment manager with four public operations: `asign`, `add`, `edit`, and `delete` (#72).
- `board-config --get-model <tier> --provider|--effort|--json` — registry-aware model resolution with provider and reasoning-effort flags (#72).
- `skills/board-model/SKILL.md` — skill definition and user-facing documentation for model/provider management (#72).
- `test_board_model.sh` — 58 tests covering validation, operations, resolution, persistence, and backward compatibility (#72).

### Fixed
- SessionStart hook: path-independent board-status resolution, bounded output (#104).
- OpenCode board tools renamed from dotted (`board.status`/`board.next`/`board.sync`) to underscore (`board_status`/`board_next`/`board_sync`) so providers that enforce the `^[a-zA-Z0-9_-]+$` tool-name pattern (e.g. DeepSeek) accept them instead of erroring on every call (#81).
- Agent-spawn surface race: parse the authoritative surface ref directly from `cmux new-split` output instead of before/after whole-tree diffing + `sleep 1` + `comm -13`, eliminating a race where two parallel spawns could select the same surface (#77).

### Changed
- Expanded `.task-spec.md` template with exact paths, verification commands, commit instructions, and scope boundaries (L10).
- `board-config --get-model` now resolves through the `model-registry` in `.tasks/config.json` when a tier is assigned to a registry entry, falling back to bare model IDs and built-in defaults (#72).
- `agent-spawn.sh` tier-resolution path now consumes registry provider and reasoning effort from `board-config --get-model <tier> --provider|--effort`, so configured backends and Codex effort affect actual dispatch (#72).

## [0.5.0] - 2026-06-12

### Added
- Codex plugin adapter (#40).
- `board-status --json --ready-tasks N` — counts + next-N ready tasks in one compact call so the orchestrator/board-plan skip the full board.json read (#50).
- cmux-agent-workflows-lite skill — compact delegation reference loaded per session instead of the full ~9.7 KB skill (#49).
- `--quiet` / `LOG_LEVEL` gate for `lib.sh log()` — background poll/spawn scripts can suppress progress chatter while still emitting their final result line (#51).

### Fixed
- Agent readiness probe is now reflow-tolerant and quiet — `agent-spawn.sh` no longer emits false 120s timeout warnings in narrow split panes, and per-poll screen output no longer leaks to the caller (#54, closes L5).
- Codex completion wait now listens to the cmux notification stream even without opencode plugin files, so CTB-DONE wakes the orchestrator before the poll fallback (#71).

### Changed
- Plugin payload relocated to `plugins/cmux-todo-board/`; Codex marketplace now installs a working plugin (#40).
- `docs/ORCHESTRATOR.md` symbol-compressed ~20–30% (bullet-dense) with no loss of rules; delegation-cycle anchor preserved (#55).
- Delegation cycle consolidated into a single canonical `docs/ORCHESTRATOR.md`; board-run-ready and cmux-agent-workflows skills link to it instead of duplicating the steps (#53).
- Orchestrator no longer reads `TODO.md`; counts/next-ready come from `board-status`. `TODO.md` is still generated as a human reference (#52).
- **Standby after dispatch** — new canonical rule in `docs/ORCHESTRATOR.md#standby-after-dispatch`: orchestrator must not actively poll the agent pane or type into it after dispatch. Cross-referenced from board-onboard-lite, board-run-ready, cmux-agent-workflows, and codex-port (#70).

## [0.4.1] - 2026-06-11

### Added
- **#34:** `bin/limit-monitor` — weekly Claude Code limit monitor (parses status-line `rate_limits.seven_day`, persists `.tasks/limit-monitor.json`, WARN/CRIT thresholds with once-per-week dedup, `cmux notify` on CRIT, graceful degrade).
- **L4:** `skills/cmux-agent-workflows/scripts/agent-audit.sh` — audit open cmux panes, reclaim idle/finished agent surfaces (dry-run default, `--apply`, safety guards).

### Changed
- Agents now maintain CHANGELOG.md via the task spec; orchestrator no longer hand-edits it (L2).

## [0.4.0] - 2026-06-11

### Added
- **Event-driven completion wait (#44):** new `poll-wait.sh` — a dual-source
  waiter that detects agent completion via the `cmux events` stream (agent idle /
  `CTB-DONE` notify) with `poll-push.sh` demoted to a fallback (bash-native
  watchdog, no GNU `timeout` dependency). Graceful degradation to poll-only when
  the cmux hooks plugin is absent.
- `board-release` — stack-agnostic SemVer release helper with safety gates (#28).

### Changed
- **Token-efficiency pass (#42):** 7 changes cutting recurring token overhead
  across board commands and agent dispatch.
  - `board-pull`: removed `body` from default `--json` fields; added `--with-body` flag.
  - `board-render`: only materialises full body `.md` for `ready` status; writes
    `body_preview` (200 chars) + `body_sha` into `board.json` for all issues.
  - `board-render-body <N>`: new command for on-demand full-body retrieval.
  - `board-onboard-lite`: compact orchestrator bootstrap SKILL.md; full rules
    moved to `docs/ORCHESTRATOR.md`.
  - `board-plan`: cap mirrored ready tasks at 5 with `… and N more` summary line.
  - `board-run-ready`: dispatch generates compact `.task-spec.md` inside agent worktree
    instead of bare URL.
  - Agent guard: `.task-spec.md` includes `forbidden_reads` forbidding glob-read of
    `.tasks/issues/*`.

### Fixed
- `agent-notify.sh`: emit structured `cmux notify --title/--body/--surface`
  instead of a bare positional payload (#44).

### Docs
- `docs/research/cmux-notify-feed-orchestrator.md` — design for event-driven
  completion wait (L1 research, #45).

## [0.3.0] - 2026-06-09

### Added
- `board-sync` — write a single issue's status back to GitHub labels,
  making the board bidirectional (#5).
- `board-add --set <id> --status <status>` — update an existing local task's
  status atomically (#16).

### Docs
- Delegation model policy documented in `docs/delegation-policy.md` (#26).
- Dispatch/spec files must live inside the agent worktree, not `/tmp` (#20).
- Agent completion notification flow documented in
  `docs/agent-notifications.md` (#21).
- Explicit orchestrator delegation rule in `board-onboard` (#22).

## [0.2.0] - earlier

### Changed
- Bumped version so `/plugin marketplace update` re-installs the cache copy.
