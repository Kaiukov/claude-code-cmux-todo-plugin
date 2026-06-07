---
name: board-pull
description: Fetch GitHub Issues and render the local task board.
---

# board-pull

Fetches GitHub issues via the `gh` CLI, writes `.tasks/issues.json`, then runs
`board-render` to produce `.tasks/board.json` and `TODO.md`.

## Usage

Run `board-pull` directly (it's in `bin/` on PATH while plugin is enabled):

```bash
board-pull --repo owner/repo
```

Optional filters:
- `--label inbox,ready` — comma-separated label filter
- `--assignee username`
- `--milestone "Sprint 1"`

Or set `BOARD_REPO` environment variable.

## What it does

1. Checks GitHub API rate limit; fails with a clear message if exhausted.
2. Fetches open issues matching the filters via `gh issue list --json`.
3. Handles pagination (up to 1000 issues via `--limit`).
4. Writes raw response to `.tasks/issues.json`.
5. Runs `board-render` to generate `.tasks/board.json` and `TODO.md`.
6. Prints a summary: total issues, ready count, blocked count.

## After running

Review `TODO.md` or `.tasks/board.json`. Then use `/board-plan` to create the
current round's plan in Claude's built-in task list.
