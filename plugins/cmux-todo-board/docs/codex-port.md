# Codex Port

This repo already ships the shared cmux runtime. The Codex adapter is a thin
plugin-facing layer: manifest + marketplace entry + docs + prompt template.
Do not duplicate the worker runtime or board logic.

## Format Parity

| Surface | Claude Code path | Codex path | Notes |
|---|---|---|---|
| Plugin manifest | `.claude-plugin/plugin.json` | `.codex-plugin/plugin.json` | Same plugin identity and metadata; only the manifest entry point changes. |
| Marketplace file | `.claude-plugin/marketplace.json` | `.agents/plugins/marketplace.json` | Codex uses a repo-scoped marketplace catalog; the plugin source stays local to this repo. |
| Skills | `skills/*/SKILL.md` | `skills/*/SKILL.md` | Shared verbatim. |
| Hooks | `hooks/hooks.json` | `hooks/hooks.json` | Shared verbatim. |
| Worker scripts | `skills/cmux-agent-workflows/scripts/*` | `skills/cmux-agent-workflows/scripts/*` | Shared backend-agnostic dispatch, wait, notify, and cleanup helpers. |
| Board cache | `.tasks/*` | `.tasks/*` | Shared cache and state model. |
| Board logic | `bin/board-*` | `bin/board-*` | Shared commands and label/state flow. |

The only plugin-packaging split is the manifest and marketplace entry point.
Everything else is reused as-is.

## Install And Run

1. Add the marketplace to Codex:

   ```bash
   codex plugin marketplace add Kaiukov/claude-code-cmux-todo-plugin
   ```

2. Install the board plugin from that marketplace:

   ```bash
   codex plugin add cmux-todo-board@kaiukov-tools
   ```

3. Start a clean Codex session and load the same board onboarding flow used by
   Claude Code. Do not fork `board-onboard`; the orchestrator identity changes,
   not the board/runtime.

   ```text
   /board-onboard
   ```

4. From the repo, pull and plan:

   ```bash
   /board-pull --repo owner/repo
   /board-plan
   ```

5. Dispatch ready work:

   ```bash
   /board-run-ready
   ```

## Backend Routing

Worker backend selection is config-driven. New scripts must not hardcode model
IDs.

- `bin/board-config --get-model <tier>` resolves the tier to a model id.
- `skills/cmux-agent-workflows/scripts/agent-spawn.sh <split> <wt> <model|tier> [label] [extra] --agent codex|opencode`
  routes the pane to the correct backend.
- Concrete Codex example:

  ```bash
  agent-spawn.sh right <wt> simple <label> -c model_reasoning_effort=high --agent codex
  ```

- `agent-send.sh` and `agent-kill.sh` accept the same backend split via
  `--kind codex` / `--agent codex`.

## Completion Loop

Workers end with the shared completion path:

- `skills/cmux-agent-workflows/scripts/agent-notify.sh` emits the CTB-DONE
  payload as the final step.
- `skills/cmux-agent-workflows/scripts/poll-push.sh` remains the fallback if the
  notification path is missed.

There is no Codex-specific finish path. The same `agent-notify.sh` and
`poll-push.sh` logic is reused by both backends.

## Worker Prompt Template

The bounded worker final-report format lives at
`skills/cmux-agent-workflows/templates/worker-prompt.md`. It is backend-agnostic
and should be used for both Codex and opencode workers.

Required final-report fields:

- `STATUS`
- `ISSUE`
- `BACKEND`
- `BRANCH`
- `FILES_CHANGED`
- `TESTS`
- `SUMMARY`
- `BLOCKERS`
- `NEXT_ACTION`

Keep the report to 20 lines or fewer.

## GPT-As-Orchestrator Note

If GPT or Codex is acting as the orchestrator, keep the same board workflow and
cmux runtime. The only thing that changes is the worker backend flag:
`--agent codex` when dispatching a Codex worker.

## Manual Smoke Test

1. Run `/board-pull --repo owner/repo`.
2. Mark one issue `ready` in GitHub if none are ready yet.
3. Run `/board-plan`.
4. Run `/board-run-ready` and confirm a Codex worker pane launches.
5. Wait for the worker's final report and `CTB-DONE` notify.
6. Run the hard gate yourself: full tests plus `claude plugin validate .`.
7. Merge only after the hard gate passes.
