# Architecture — cmux-todo-board plugin

End-to-end system design: how GitHub Issues become dispatched work in cmux panes,
how status flows back, and where each component lives.

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GITHUB (source of truth)                     │
│  Issues + labels (status)                                           │
└──────────────┬──────────────────────────────────────┬───────────────┘
               │ board-pull (gh api)                  │ board-sync (gh api)
               ▼                                      ▲
┌──────────────────────────────┐    ┌─────────────────────────────────┐
│       .tasks/issues.json     │    │      board-sync                 │
│       (raw API cache)         │    │      (write ONE status label)  │
└──────────────┬───────────────┘    └─────────────────────────────────┘
               │ board-render (Python)
               ▼
┌──────────────────────────────┐
│       .tasks/board.json      │  ◄── single local source of truth
│       (derived + local)      │
└──────┬───────────┬───────────┘
       │           │ board-render (Python)
       │           ▼
       │  ┌────────────────────┐
       │  │     TODO.md         │  ◄── read-only human view
       │  │  (generated, never  │
       │  │   hand-edited)      │
       │  └────────────────────┘
       │
       │ board-plan (skill)
       ▼
┌──────────────────────────────┐
│   Claude built-in task list   │  ◄── ephemeral round plan (≤5 ready)
└──────────────┬───────────────┘
               │ board-run-ready (skill + scripts)
               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        CMUX RUNTIME                                 │
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                         │
│  │ surface 1 │  │ surface 2 │  │ surface 3 │  ◄── panes (tabs/splits) │
│  │ wt-XXX/   │  │ wt-YYY/   │  │ (orchestr) │                        │
│  │ Pi/Codex  │  │ Pi/Codex  │  │           │                        │
│  └─────┬─────┘  └─────┬─────┘  └───────────┘                        │
│        │              │                                             │
│        │  poll-wait.sh (event-driven + poll fallback)                │
│        │  agent-screen.sh (read final output)                       │
│        │  agent-send.sh (inject task spec)                          │
│        │  agent-notify.sh (CTB-DONE signal)                         │
│        ▼              ▼                                             │
│  ┌──────────────────────────────────────────┐                      │
│  │   .task-spec.md (in agent worktree)       │                      │
│  │   worker-status widget (Pi extension)     │                      │
│  └──────────────────────────────────────────┘                      │
└─────────────────────────────────────────────────────────────────────┘
               │
               │ pr-finish.sh (merge + cleanup)
               │ verify.sh / verify-ts.sh (hard gate)
               ▼
┌──────────────────────────────┐
│         MAIN branch           │  ◄── squashed merge
└──────────────────────────────┘
```

## Data Flow

### Pull (GitHub → local)

```
gh api /repos/:owner/:repo/issues
    │
    ▼
.tasks/issues.json          ← raw JSON cache (board-pull only)
    │
    ▼ board-render
.tasks/board.json           ← normalized, enriched with local tasks
    │
    ├──► board-status        ← compact summary for orchestrator
    ├──► board-next          ← next actionable task
    └──► TODO.md             ← human-readable render
```

### Plan (local → built-in task list)

```
board-plan skill reads .tasks/board.json
    │
    ▼ filters status=ready, caps at 5
Claude built-in task list     ← ephemeral, discarded at round end
```

### Dispatch (built-in list → cmux pane)

```
board-run-ready skill
    │
    ├──► wt-new.sh           ← git worktree add (off origin/main)
    ├──► agent-spawn.sh      ← cmux new-split + Pi/Codex launch
    ├──► agent-send.sh       ← write .task-spec.md into worktree
    └──► poll-wait.sh        ← background: wait for completion
```

### Completion detection

```
Two-path waiter (poll-wait.sh):
    │
    ├── PRIMARY: cmux events --category agent --category notification
    │            (agent idle / Stop / CTB-DONE notify)
    │
    └── FALLBACK: poll-push.sh
                 (git push detection in worktree)
```

### Verify & merge

```
agent done signal
    │
    ├──► verify.sh / verify-ts.sh   ← typecheck + tests (hard gate)
    ├──► pr-finish.sh               ← squash merge + cleanup
    └──► agent-audit.sh             ← reclaim idle panes
```

### Sync-back (local → GitHub)

```
board-sync --issue N --status STATUS
    │
    ▼ gh api PATCH /repos/:owner/:repo/issues/N
         swaps old canonical label → new label
         leaves non-canonical labels untouched
         idempotent (no-op if same status)
```

## Boundary Map

| Layer | What lives here | Key files |
|-------|----------------|-----------|
| **GitHub** | Issues, labels (source of truth for STATUS) | — |
| **Plugin — bin scripts** | Bash/Python executables called by skills or directly | `bin/board-pull`, `bin/board-render`, `bin/board-status`, `bin/board-next`, `bin/board-sync`, `bin/board-add`, `bin/board-release`, `bin/board-model`, `bin/board-config`, `bin/board-render-body`, `bin/board-init`, `bin/limit-monitor` |
| **Plugin — skills** | Claude Code skill definitions (markdown instructions) | `skills/*/SKILL.md` |
| **Plugin — hooks** | Lifecycle hooks (SessionStart board summary) | `hooks/hooks.json` |
| **Plugin — agent scripts** | cmux agent lifecycle scripts | `skills/cmux-agent-workflows/scripts/` — `wt-new.sh`, `agent-spawn.sh`, `agent-send.sh`, `agent-screen.sh`, `poll-wait.sh`, `poll-push.sh`, `verify.sh`, `verify-ts.sh`, `pr-finish.sh`, `agent-kill.sh`, `agent-audit.sh`, `agent-notify.sh` |
| **Plugin — docs** | Design & reference docs | `docs/state-model.md`, `docs/file-roles.md`, `docs/ORCHESTRATOR.md`, `docs/delegation-policy.md`, `docs/orchestrator-token-efficiency.md`, `docs/agent-notifications.md`, `docs/ARCHITECTURE.md` |
| **Plugin — OpenCode** | OpenCode-native orchestrator entrypoint | `.opencode/agent/orchestrator.md`, `.opencode/plugins/cmux-board.mjs` |
| **cmux runtime** | Terminal multiplexer — panes, splits, events, notify feed | cmux binary (external) |
| **Pi / Codex agents** | Worker coding agents in cmux panes | Pi (`pi`), Codex (`codex`) — external |
| **.tasks/** | Local state directory (gitignored) | `issues.json` (API cache), `board.json` (local truth), `local.json` (local tasks), `issues/*.md` (body cache), `config.json` (settings) |
| **Worktree** | Per-task git worktree (sibling dir, carries `.env`) | `.task-spec.md`, repo files |

## Orchestrator Role

The orchestrator (Claude running in the main cmux pane) coordinates — never implements:

1. **Triage:** `board-pull` → `board-status`
2. **Plan:** `board-plan` → mirror ≤5 ready tasks
3. **Delegate:** `board-run-ready` → dispatch to cmux panes
4. **Standby:** wait for completion signal (never poll the agent pane)
5. **Verify:** `verify.sh` + `pr-finish.sh` (hard gate, never trust agent self-report)
6. **Cleanup:** `agent-audit.sh` → reclaim idle panes

See `docs/ORCHESTRATOR.md` for full rules including standby-after-dispatch, token efficiency, and task classification (strategic keep / tactical delegate / mechanical delegate).

## State Model

| Concern | Representation | Authority |
|---------|---------------|-----------|
| STATUS | GitHub Issue labels | **Source of truth** |
| Local cache | `.tasks/board.json` | Derived from issues + local annotations |
| Read-only view | `TODO.md` | Regenerated, never hand-edited |
| Ephemeral plan | Claude built-in task list | Current round only; discarded at round end |

Canonical status flow: `inbox → ready → in-progress → needs-review → done`

See `docs/state-model.md` for the full mapping table across GitHub labels / board.json / Claude task states, bidirectional sync rules, and session recovery.

## File Roles

| File | Role | Written by | Editable? |
|------|------|-----------|-----------|
| `.tasks/issues.json` | Raw GitHub API cache | `board-pull` | ❌ never hand-edit |
| `.tasks/board.json` | Local source of truth | `board-render` | ❌ never hand-edit |
| `TODO.md` | Human-readable render | `board-render` | ❌ generated, do not edit |
| `.tasks/local.json` | Local-only tasks (no GitHub) | `board-add` | ✅ via board-add only |
| `.tasks/config.json` | Plugin settings | `board-config` | ✅ via board-config only |

See `docs/file-roles.md` for full specification.

## Agent Script Reference

All in `skills/cmux-agent-workflows/scripts/`:

| Script | Purpose | Called by |
|--------|---------|-----------|
| `wt-new.sh` | Create git worktree off origin/main | orchestrator (dispatch) |
| `agent-spawn.sh` | Launch cmux pane + Pi/Codex agent | orchestrator (dispatch) |
| `agent-send.sh` | Write `.task-spec.md` into worktree | orchestrator (dispatch) |
| `agent-screen.sh` | Read final output from agent pane | orchestrator (after done) |
| `poll-wait.sh` | Event-driven + poll fallback completion wait | orchestrator (background) |
| `poll-push.sh` | Git push detection fallback | poll-wait.sh (internal) |
| `verify.sh` | Shell test runner | orchestrator (hard gate) |
| `verify-ts.sh` | TypeScript checker | orchestrator (hard gate) |
| `pr-finish.sh` | Squash merge + cleanup | orchestrator (after verify) |
| `agent-kill.sh` | Tear down agent pane | orchestrator (cleanup) |
| `agent-audit.sh` | Audit panes, reclaim idle surfaces | orchestrator (round end) |
| `agent-notify.sh` | Emit CTB-DONE notification | worker agent (on completion) |
| `lib.sh` | Shared logging + helpers | all scripts |

## Model Tiers

Configured via `board-config --set-model <tier> <provider/model>` or directly in `.tasks/config.json`.

| Tier | Default model | Role |
|------|--------------|------|
| `flash` | `opencode/deepseek-v4-flash-free` | Mechanics, docs, routine, config/tests |
| `pro` | `opencode-go/deepseek-v4-pro` | Complex / reasoning-heavy implement |
| `review` | `codex gpt-5.4` | Review of heavy/financial PRs |
| `simple` | `codex gpt-5.4-mini` | Simple/docs on codex side |
| `top` | `codex gpt-5.5` | Exceptional complexity; explicit request only |

`agent-spawn.sh` resolves the agent model via `board-config --get-model <tier> --provider|--effort`.

See `docs/delegation-policy.md` for full rules.

## Pi Worker Extensions

Workers (Pi in cmux panes) can run extensions for observability:

| Extension | Location | Purpose |
|-----------|----------|---------|
| `cmux-session.ts` | `~/.pi/agent/extensions/` | Bridges Pi lifecycle events → cmux session store |
| `worker-status.ts` | `~/.pi/agent/extensions/` | Renders self-status widget above editor (planned per #95) |

See `docs/research/pi-worker-status-widget.md` for the widget design.

## OpenCode Plugin

The `.opencode/` directory provides a native OpenCode plugin entrypoint:

| File | Purpose |
|------|---------|
| `agent/orchestrator.md` | OpenCode orchestrator agent definition |
| `plugins/cmux-board.mjs` | Custom tools: `board_status`, `board_next`, `board_sync` + `shell.env` + `session.idle` hooks |

The orchestrator agent is configured with `mode: primary` and encodes the full delegation cycle, board workflow, and standby rules.

## Design Docs Map

| Doc | Covers |
|-----|--------|
| `docs/ARCHITECTURE.md` (this file) | System overview, component diagram, data flow, boundaries |
| `plugins/cmux-todo-board/docs/state-model.md` | Status enum, 4-representation mapping, sync, recovery |
| `plugins/cmux-todo-board/docs/file-roles.md` | Which file is canonical vs derived vs generated |
| `plugins/cmux-todo-board/docs/ORCHESTRATOR.md` | Orchestrator role, delegation cycle, task spec format, standby |
| `plugins/cmux-todo-board/docs/delegation-policy.md` | Model tiers, routing rules, avoid list |
| `plugins/cmux-todo-board/docs/orchestrator-token-efficiency.md` | Behavioural guardrails, model routing, tool budgets, handoff template |
| `plugins/cmux-todo-board/docs/agent-notifications.md` | Completion notification flow (CTB-DONE, event stream) |
| `plugins/cmux-todo-board/docs/cmux-cheat-sheet.md` | cmux CLI reference (notify, feed, panes) |
| `ISSUES.md` | Issue backlog & design plan (may drift from implementation) |
| `CHANGELOG.md` | Release history |
| `README.md` | Quick start, installation, workflow, skill catalog |

## Key Design Decisions

1. **GitHub labels are the source of truth for status** — not board.json, not TODO.md, not Claude's built-in task list. This survives session loss.
2. **One-directional MVP first** — pull→render→plan→dispatch was built and battle-tested before bidirectional sync-back was added.
3. **Task specs live inside the agent worktree** — never in `/tmp` or external dirs, avoiding permission prompts and keeping dispatch self-contained.
4. **Hard gate is always the orchestrator's** — agents never self-verify; the orchestrator independently runs tests + typecheck + live check before merge.
5. **Standby after dispatch** — orchestrator must not poll or type into worker panes; waits for event-driven completion signal.
6. **Pi as worker, not sub-agent pool** — one Pi per cmux pane in a git worktree; completion via cmux `agent.hook.Stop` event; truth via git push. Self-status widget is additive observability (no sub-agent management).
