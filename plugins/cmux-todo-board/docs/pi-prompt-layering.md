# Pi Worker Prompt Layering Design

## Overview

Pi workers receive behavior rules through three distinct layers, each owned by
a different part of the system. The orchestrator writes a tiny dispatch message;
stable rules live in repo-owned prompt assets loaded via CLI flags.

## Layers

### Layer 1 — universal system base (`common-system.md`)
Stable, project-agnostic rules loaded for **every** Pi worker, every role,
every project: operate inside the assigned worktree, read the task spec,
respect scope and boundaries, run verification, never deploy to production,
never leak secrets, emit a compact final report, and signal completion.
This file is kept short (~20–30 lines) and never contains role-specific or
repo-specific content.

### Layer 2 — per-role guidance assets (`roles/*.md`)
Tiny files (~15–20 lines each) containing only what differs by role: mission,
allowed and prohibited work, verification emphasis, and output expectations.
They never repeat common-system rules.

The asset loaded is chosen by the profile's **`role` field**, not the profile
name. This decouples the asset filename from the profile identity: multiple
profiles can share the same role asset (e.g. `backend-fast`, `test`, and
`tiny-patch` all use `roles/backend.md`). The mapping is:

| Role          | Asset file                          | Profiles using it                                   |
|---------------|-------------------------------------|-----------------------------------------------------|
| `backend`     | `prompts/pi/roles/backend.md`       | backend, backend-fast, test, tiny-patch             |
| `docs`        | `prompts/pi/roles/docs.md`          | docs                                                |
| `frontend`    | `prompts/pi/roles/frontend.md`      | frontend                                            |
| `frontend-top`| `prompts/pi/roles/frontend-top.md`  | frontend-top                                        |
| `review`      | `prompts/pi/roles/review.md`        | review, repo-scout                                  |

### Layer 3 — task spec (`.task-spec.md`)
Carries ALL repo- and task-specific information: the task description, exact
file paths, verification commands, commit instructions, scope boundaries, and
forbidden reads/writes. This is written per-task by the orchestrator and lives
inside the worker's worktree.

## File Layout

```
plugins/cmux-todo-board/prompts/pi/
  common-system.md      # Layer 1 — universal base
  roles/
    backend.md          # Layer 2 — backend role
    frontend.md         # Layer 2 — frontend role
    frontend-top.md     # Layer 2 — frontend-top role
    review.md           # Layer 2 — review role (read-only enforced)
    docs.md             # Layer 2 — docs role
```

### Why inside `plugins/cmux-todo-board/` instead of a `.pi/` root directory?

1. **Packaged and installable.** The plugin is the distribution unit (OpenCode
   marketplace, Codex, Claude Code). Putting prompt assets under the plugin
   means they are versioned, shipped, and updated together with the plugin
   — no separate installation step.

2. **Passed via CLI flags, not echoed into orchestrator context.** The assets
   are loaded with `--append-system-prompt <path>` on the Pi launch command.
   The orchestrator never reads or echoes their contents, saving significant
   token overhead on every dispatch (~2–3 KB per spawn).

3. **Project-local ownership.** Unlike a root `.pi/` directory, assets live
   where the project already manages plugin configuration. No new top-level
   directory to document or maintain.

## Dispatch Contract

```
Orchestrator                    agent-spawn.sh                 Pi Worker
───────────                    ──────────────                 ─────────
1. Select role via
   --profile <name>

                               2. Resolve profile (#102)
                                  → {provider, model, thinking,
                                     tools, role}

                               3. Build extra args:
                                  --append-system-prompt
                                    .../common-system.md
                                  --append-system-prompt
                                    .../roles/<role>.md

4. Write .task-spec.md
   into worktree

                               5. Launch Pi with:
                                  pi --provider ... --model ...
                                     --append-system-prompt .../common-system.md
                                     --append-system-prompt .../roles/<role>.md

                                                              6. Pi loads system
                                                                 prompt assets

                                                              7. Pi reads
                                                                 .task-spec.md
                                                                 and executes
                                                                 only that task
```

### Critical rule: orchestrator must NOT load asset contents

The orchestrator writes the task spec and selects the role. It does **not** read
or echo the contents of `common-system.md` or `roles/*.md` into its own context.
Those files are loaded by the launch helper into the Pi worker's system prompt
via `--append-system-prompt`. This keeps orchestrator token usage minimal and
prevents the rules from being duplicated or stale in the orchestrator's context
window.

## Design Questions (from #118)

### Skills vs. plain files for prompt assets?
Plain markdown files. Skills carry execution instructions and metadata for the
orchestrator; these are simple text assets loaded by Pi's CLI. Making them skills
would add loading overhead with no benefit.

### Who owns the file paths?
The `agent-spawn.sh` launch helper (inside the plugin's scripts directory).
It resolves absolute paths using `$DIR/../../../prompts/pi/`, so they work
regardless of the current working directory.

### When would `--no-context-files` be used?
For debugging or when a worker needs a completely blank system prompt (e.g.,
testing prompt isolation). The flag suppresses all `--append-system-prompt`
arguments. This is a Pi CLI feature; the launch wiring doesn't use it.

### Packaging concerns?
All prompt assets live under `plugins/cmux-todo-board/prompts/pi/`. They are
shipped with the plugin and installed together. No additional packaging step
is required — they are available as soon as the plugin is installed.
