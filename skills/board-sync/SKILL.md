---
name: board-sync
description: Write ONE issue's status back to GitHub by swapping its canonical label. Idempotent, preserves non-canonical labels.
---

# board-sync

Writes an issue's canonical status label to GitHub — the board → GitHub
direction. This **WRITES** to GitHub; always confirm the repository before use.

```
/board-sync --issue N --status STATUS [--repo OWNER/REPO]
```

## What it does

1. Fetches the issue's current labels via `gh issue view`.
2. Computes which canonical label to remove (if any) and which to add.
   Non-canonical labels (bug, enhancement, …) are left untouched.
3. If the issue already has the target status, it is a no-op.
4. Applies the label swap via `gh issue edit`.
5. Prints a one-line result (e.g. `#5: ready -> in-progress`).

## Usage notes

- Repo is resolved from `--repo` or the `BOARD_REPO` env var.
- Valid statuses: inbox, ready, in-progress, needs-review, blocked, needs-info, done.
- Single issue only — no batch. Explicit, not automatic.
