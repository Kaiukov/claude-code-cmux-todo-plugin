# Changelog

All notable changes to this project are documented here.
This project adheres to semantic versioning.

## [Unreleased]

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

### Added
- `board-release` — stack-agnostic SemVer release helper with safety gates (#28).

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
