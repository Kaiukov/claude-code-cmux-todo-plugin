---
name: board-init
description: Initialize a GitHub repo with canonical board status labels. Run once per repo before board-pull. Idempotent — safe to re-run.
---

# board-init

Creates or normalizes the 7 canonical board status labels in a GitHub repository:
`inbox`, `ready`, `in-progress`, `needs-review`, `blocked`, `needs-info`, `done`.

Run this **once per repo** before using `board-pull`. It is idempotent — re-running
is safe and will simply update colors and descriptions to match the canonical values.
Unrelated labels are never touched.

## Usage

```bash
board-init --repo owner/repo
```

Or set the `BOARD_REPO` environment variable:

```bash
export BOARD_REPO=owner/repo
board-init
```

## What it does

1. Creates or updates each of the 7 canonical status labels via `gh label create --force`.
2. Sets the canonical color and description for each label.
3. Does NOT delete or modify any other labels in the repository.

## After running

Once labels exist, use `/board-pull` to fetch and render the board.
