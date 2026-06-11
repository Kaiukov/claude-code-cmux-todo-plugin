---
name: board-create-issue
description: Turn a raw, unstructured task description into a well-formed GitHub issue and create it. Usage — /board-create-issue <raw task text>. The agent analyzes the input, drafts a clear title + body + acceptance criteria, picks a canonical status label, and runs `gh issue create`.
---

# board-create-issue

Takes a **raw task description** (the text after the command) and creates a
properly structured GitHub issue on the board's repo.

```
/board-create-issue <raw task text>
```

## Prerequisites

- `gh` (GitHub CLI) authenticated.
- Repo resolved from `--repo owner/repo`, `$BOARD_REPO`, or the current repo.
- Canonical labels must exist on the repo — run `/board-init` once first.

## Procedure

1. **Parse the raw input.** Everything after the command is the raw task. If a
   `--repo owner/repo` is present, use it; otherwise use `$BOARD_REPO` or the
   current repo (`gh repo view`). If no repo can be resolved, ask the user.

2. **Analyze and structure.** From the raw text, produce:
   - **Title** — concise, imperative, prefixed by type when obvious
     (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`). Max ~70 chars.
   - **Body** — markdown with these sections (omit a section only if truly N/A):
     - `## Context` — what/why, restating the raw intent in clear terms.
     - `## Acceptance criteria` — a checklist (`- [ ]`) of concrete, testable
       outcomes inferred from the task.
     - `## Notes` — assumptions made, open questions, or scope boundaries.
   - Do **not** invent requirements that contradict the raw text. Where the task
     is ambiguous, capture the ambiguity under `## Notes` rather than guessing.

3. **Pick a status label.** Default to **`inbox`** (new, untriaged). Use
   `ready` ONLY if the task is unambiguous and immediately actionable. Never set
   `in-progress`, `needs-review`, or `done` on creation. If genuinely blocked or
   under-specified, use `needs-info`.

4. **Create the issue.** Pass the body via a temp file or heredoc to preserve
   markdown/newlines:
   ```bash
   gh issue create --repo "$REPO" \
     --title "<title>" \
     --body-file <(printf '%s\n' "$BODY") \
     --label "<status-label>"
   ```
   Add extra non-status labels (e.g. `enhancement`, `bug`) when clearly implied,
   but only if they already exist on the repo (`gh label list`).

5. **Report.** Print the created issue number, title, label, and URL. Suggest
   `/board-pull` to refresh the local board.

## Notes

- Generate issue titles and bodies in the configured language (`board-config --get`); default **EN**.
- This skill WRITES to GitHub (creates an issue). It is the one board command
  besides `board-init` that mutates the remote repo. Confirm the resolved repo
  before creating if there is any doubt about which repo is active.
- One invocation = one issue. For a batch, run the command per task.
