# Changelog

All notable changes to this project are documented here.
This project adheres to semantic versioning.

## [Unreleased]

### Added
- Codex plugin adapter (#40).
- `board-status --json --ready-tasks N` — counts + next-N ready tasks in one compact call so the orchestrator/board-plan skip the full board.json read (#50).
- cmux-agent-workflows-lite skill — compact delegation reference loaded per session instead of the full ~9.7 KB skill (#49).
- `--quiet` / `LOG_LEVEL` gate for `lib.sh log()` — background poll/spawn scripts can suppress progress chatter while still emitting their final result line (#51).

### Fixed
- Agent readiness probe is now reflow-tolerant and quiet — `agent-spawn.sh` no longer emits false 120s timeout warnings in narrow split panes, and per-poll screen output no longer leaks to the caller (#54, closes L5).

### Changed
- Plugin payload relocated to `plugins/cmux-todo-board/`; Codex marketplace now installs a working plugin (#40).
- `docs/ORCHESTRATOR.md` symbol-compressed ~20–30% (bullet-dense) with no loss of rules; delegation-cycle anchor preserved (#55).
- Delegation cycle consolidated into a single canonical `docs/ORCHESTRATOR.md`; board-run-ready and cmux-agent-workflows skills link to it instead of duplicating the steps (#53).
- Orchestrator no longer reads `TODO.md`; counts/next-ready come from `board-status`. `TODO.md` is still generated as a human reference (#52).

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
