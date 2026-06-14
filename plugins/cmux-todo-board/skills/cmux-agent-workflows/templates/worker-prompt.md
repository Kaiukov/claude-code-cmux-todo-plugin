# Worker Prompt Template

- Work only inside the assigned worktree.
- Keep the fix additive and bounded to the task scope.
- If you discover unrelated work, do not expand the task; report it in
  `BLOCKERS` or `NEXT_ACTION`.
- The final step is to commit on the branch, then return the short final report below.

## Final Report

```text
STATUS: success|failure
ISSUE: #<id> <title>
BACKEND: codex|opencode
BRANCH: <branch>
FILES_CHANGED:
- <path>
TESTS:
- <command> -> <pass|fail>
SUMMARY: <1-3 sentences>
BLOCKERS: none|<short note>
NEXT_ACTION: <short imperative>
```
