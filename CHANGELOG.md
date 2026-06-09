# Changelog

All notable changes to this project are documented here.
This project adheres to semantic versioning.

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
