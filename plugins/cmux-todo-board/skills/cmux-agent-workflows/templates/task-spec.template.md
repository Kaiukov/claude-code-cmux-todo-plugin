<!--
  This is a maximally-detailed fill-in-the-blanks template for dispatched workers.
  Replace every `<ANGLE_BRACKET>` placeholder before handing the spec to the worker.
  Sections marked "OPTIONAL" may be omitted when the task is fully scoped in the
  existing spec and no parallel writes or sourcing concerns apply.
-->

# Task: <one-line title> (<issue/local id>)

## Goal

<2–4 sentences: what the worker must produce, why it matters, what value it
delivers. Set the objective in concrete, testable terms. Avoid implementation
details — those belong in Behavior / Contract.>

## Source (OPTIONAL — delete heading + body if not applicable)

- **Upstream repo / license:** `<https://github.com/owner/repo>`  (`<LICENSE>`)
- **Files to port:** `<path1, path2, …>` — only the files needed for this task.
- **Attribution:** retain original copyright / license header in ported files;
  add `(port from <upstream>, <date>)` to the commit body.

## Files (create/edit ONLY these)

Create:
- `<path/to/new/file>` — `<brief description of purpose>`

Edit:
- `<path/to/existing/file>` — `<what changes are needed>`

> **DO NOT** touch any file outside this list, including source/config/launch code,
> unless the task explicitly permits it under Bounds.

## CONTENTION GUARD (OPTIONAL — delete heading + body if not applicable)

When a file listed above is also being edited by a **parallel task**, use the
following contention-guard marker convention to delimit the block this worker
owns:

```
# --- <id> <topic> ---
  … code this worker may safely edit …
# --- end <id> ---
```

- **Shared file:** `<path to shared file>`
- **Contention mark:** `<id>` (e.g. `#91` damage-control)
- **This worker's block:** everything between `# --- <id> <topic> ---` and
  `# --- end <id> ---`. Do NOT edit code outside this delimiting block, even if
  the file appears in the Files list. Any change outside the block signals a
  guard violation that must be reverted.

## Behavior / Contract

<Functional rules the implementation must obey. Include:
- Input specification (argv, stdin, environment variables, config files)
- Output specification (stdout, stderr, exit code, side-effects)
- Edge cases and error handling (missing files, invalid args, broken pipes)
- Idempotency / re-entrancy guarantees (can it be run multiple times?)
- Resource constraints (timeout, memory, disk, number of parallel instances)
- Security / secret-handling rules (never log tokens, never write secrets to disk)
- If editing an existing command: backward-compatibility requirements (flag
  names, default behaviour, output format)
>

## Test

- **Test file:** `<path/to/test.sh>`
- **Assertions:** <list each test case; what it must assert — e.g. "exit 0 on
  valid input", "exit non-zero on missing file", "stdout contains expected JSON">
- **Print PASS/FAIL per case** with a descriptive label.
- **Exit non-zero** on any failure (shell `exit 1` after all cases).
- **Compatibility:** macOS bash 3.2 (no `-A` associative arrays, no `[[ ]]`,
  no `<<<` heredoc syntax, no `readarray`, no `shopt`, no `{A..B}` brace range).
  Use `printf` and `[ ]` for portability.

## Acceptance

- [ ] <Objective, verifiable check 1>
- [ ] <Objective, verifiable check 2>
- [ ] `bash <test-path>` → all PASS, exit 0
- [ ] No source/config/launch code touched (grep for files outside the Files list)

## Verify (before pushing)

```bash
cd <worktree>
bash <test-path>
```

## Commit / push

```bash
git add <path1> <path2> …
git commit -m "<type>(<scope>): <imperative description>"
git push -u origin <branch-name>
```

## CHANGELOG (under ## [Unreleased] → ### Added or ### Changed)

```
- <bullet describing the change, including relative file paths>
```

## Bounds

- Edit ONLY the files listed in "Files (create/edit ONLY these)".
- No out-of-scope edits (refactoring, renaming, style fixes, unrelated tests).
- Do NOT read `.tasks/issues/*` globs (high token cost; use `board-status --json` instead).
- No secrets — never commit tokens, keys, or passwords.
- macOS bash 3.2 compatible — no `[[ ]]`, `<<<`, `readarray`, `shopt`, associative arrays, `{A..B}` expansions.
- If the task involes a test, ensure it uses `/usr/bin/bash` or `#!/bin/bash` shebang with `set -euo pipefail`.

## Completion

When all Acceptance checks pass, the test is green, and the commit has been
pushed, print a compact report:

```
## Task complete — <one-line title> (<issue/local id>)

### Files added
- <path1>
- <path2>

### Files edited
- <path3>

### Sections confirmed present (13/13)
1. Task title ✓
2. Goal ✓
3. Source ✓
4. Files (create/edit ONLY these) ✓
5. CONTENTION GUARD ✓
6. Behavior / Contract ✓
7. Test ✓
8. Acceptance ✓
9. Verify ✓
10. Commit / push ✓
11. CHANGELOG ✓
12. Bounds ✓
13. Completion ✓

### Test results
- <N> / <N> PASS
- All tests exit 0 ✓
```
