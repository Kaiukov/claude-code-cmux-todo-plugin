# Task-spec template guide

A rigorous, maximally-detailed `.task-spec.md` template improves worker outcomes
by eliminating ambiguity about scope, file bounds, acceptance criteria,
verification steps, and commit protocol. When every dispatched worker receives
an unambiguous spec with pre-filled placeholders, the sub-agent spends less time
interpreting vague instructions and more time delivering correct, bounded work.

## Section reference

| # | Section | Required | Purpose |
|---|---------|----------|---------|
| 1 | `# Task: <title>` | required | One-line title and issue/local ID for traceability |
| 2 | `## Goal` | required | 2–4 sentences: what + why + value |
| 3 | `## Source` | optional | Upstream repo/license to port from; attribution rule |
| 4 | `## Files (create/edit ONLY these)` | required | Exact path list with NEW/edit annotation; the worker's scope boundary |
| 5 | `## CONTENTION GUARD` | optional | Marker convention for files edited by parallel tasks |
| 6 | `## Behavior / Contract` | required | Functional rules: inputs, outputs, edge cases, idempotency, security |
| 7 | `## Test` | required | Exact test path + assertions; PASS/FAIL per case; macOS bash 3.2 compat |
| 8 | `## Acceptance` | required | Objective checklist of pass conditions |
| 9 | `## Verify (before pushing)` | required | Copy-pasteable verification commands |
| 10 | `## Commit / push` | required | Exact `git add`, `git commit`, `git push` commands |
| 11 | `## CHANGELOG` | required | Exact bullet to add under `## [Unreleased]` |
| 12 | `## Bounds` | required | Forbidden paths, scope limits, shell-compat rules |
| 13 | `## Completion` | required | Compact final-report format the worker prints when done |

**Required** sections must always appear in the task spec. **Optional** sections
(Source, CONTENTION GUARD) may be deleted (heading + body) when not applicable.

## CONTENTION GUARD convention

When two parallel workers need to edit the same file, the orchestrator inserts
delimiting markers so each worker knows exactly which region it owns:

```
# --- #91 damage-control ---
  … worker #91's changes …
# --- end #91 ---
```

- The worker must edit **only** the code between `# --- <id> <topic> ---` and
  `# --- end <id> ---`, even if the shared file is listed in its Files section.
- Any change outside the block signals a **guard violation** that must be
  reverted.
- The orchestrator is responsible for inserting the markers before dispatch and
  for merging the blocks after both workers complete.

## Rule: spec must live inside the worker's worktree

The task spec **must** be placed inside the worker's worktree directory (e.g.
`<worktree>/.task-spec.md`). It must **never** reside in `/tmp` or any external
directory. This avoids "Access external directory" permission prompts from the
agent and ensures the spec is always available relative to the worker's working
directory.

## Template location

The canonical template is at:

```
plugins/cmux-todo-board/skills/cmux-agent-workflows/templates/task-spec.template.md
```

Orchestrator code that generates `.task-spec.md` for a dispatched worker should
read this template, replace `<ANGLE_BRACKET>` placeholders, and write the result
to `<worktree>/.task-spec.md`.
