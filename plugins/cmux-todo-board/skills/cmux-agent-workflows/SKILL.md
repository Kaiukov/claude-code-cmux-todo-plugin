---
name: cmux-agent-workflows
description: Advanced cmux agent orchestration helpers — on-demand / advanced only. Covers agent backends, hook installation, codex gotchas, live-deploy traps, and detailed script implementation. For routine delegation, use cmux-agent-workflows-lite.
---

# cmux agent workflows

Token-saving shell helpers for the orchestrator pattern: the main agent (Opus)
delegates ALL coding to cmux agents, then independently verifies and merges.
Each script replaces a multi-call shell sequence I would otherwise type by hand.

**Live deploy / KV writes / DB mutations stay orchestrator-only.** Agents
implement and unit-test on MOCKS; the orchestrator runs the single real
`wrangler deploy` / `kv key put --remote` / migration. Mocks pass while live
breaks — always do the live check yourself (see the `--remote` and
KV-binding traps below).

## Supported agent backends

The spawn/send/kill helpers dispatch to `pi` as the sole worker runtime.
Same rock-band tab names, same cmux hook integration, same worktree flow.

| Backend | Binary | Launched as                                              | Ready pattern on screen        |
| ------- | ------ | -------------------------------------------------------- | ------------------------------ |
| pi      | `pi`   | `cd <wt> && pi --provider <p> --model <m> [--thinking …]` | `(auto)`, `(sub)`, esc interrupt |

Auto-detect rule: agent kind is always `pi` (the only runtime).

The pi spawn script pre-seeds worktree trust in `~/.pi/agent/trust.json` so
the agent never sits waiting on a trust prompt.

`cmux hooks` install once per machine (one-line, idempotent):

```bash
yes | cmux hooks pi install
```

## Scripts (in `scripts/`)

| Script | Purpose | Example |
|---|---|---|
| `wt-new.sh <branch> <dir>` | New worktree (base overridable via `BASE_REF` env) + copy `.env` if present + `bun install` only if `package.json` exists | `wt-new.sh feat/foo ../wt-feat-foo` |
| `agent-spawn.sh <dir> <wt> <model> [label] [extra agent args...] [--agent pi]` | Split pane, boot agent, wait until ready, auto-name tab (random unused band) → echoes surface ref | `agent-spawn.sh right $WT opencode-go/deepseek-v4-pro TASK` (pi auto-detect) |
| `agent-send.sh <surface> <text…>` | Send a prompt + Enter (stdin for long prompts) | `agent-send.sh surface:172 "run tests, paste output"` |
| `agent-screen.sh <surface> [lines]` | Read a surface screen | `agent-screen.sh surface:172 30` |
| `agent-kill.sh <surface> [--agent pi] [--close]` | Kill the agent proc by tty, optionally close split | `agent-kill.sh surface:172 --agent pi --close` |
| `agent-notify.sh --task <id> --surface <ref> --status success\|failure [--branch <b>]` | Agent's FINAL step: emit CTB-DONE payload via `cmux notify` (structured flags: `--title --body --surface`) or stdout (FALLBACK). Never hard-fails. | `agent-notify.sh --task 32 --surface surface:172 --status success --branch feat/foo` |
| `poll-wait.sh --surface <ref> --branch <name> [--task <id>] [--event-timeout <s>] [--total-timeout <s>]` | **PRIMARY** dual-source wait: event-driven (`cmux events` → agent.hook.Stop / lifecycle idle / CTB-DONE) with `poll-push.sh` fallback. Run with `run_in_background:true` | `poll-wait.sh --surface surface:172 --branch feat/foo --task 44 --total-timeout 600` |
| `poll-push.sh <branch> [int] [timeout]` | **FALLBACK** git-poll: polls origin until branch pushed; print PR. Used internally by `poll-wait.sh`; not called directly in the new delegation cycle. | `poll-push.sh feat/foo 30 1800` |
| `verify.sh <wt> [base-ref]` | Project-agnostic gate: `bash -n` on changed shell scripts + `bun test`/`npm test` if a test script exists; no-op otherwise | `verify.sh $WT` |
| `verify-ts.sh <wt>` | TS-specific hard gate: typecheck + full `bun test`, exits non-zero on any failure | `verify-ts.sh ../wt-feat-foo` |
| `pr-finish.sh <pr#> [wt]` | Remove worktree, squash-merge, delete branch | `pr-finish.sh 121 $WT` |

`lib.sh` is shared (sourced by the others): `cmux_surfaces`, `cmux_tty`,
`pick_band` (random rock-band name excluding live tabs), and the
agent-dispatch helpers `agent_kind_detect`, `agent_launch_cmd`,
`agent_ready_patterns`, `agent_kill_pattern`, `wait_agent_ready`. Not run
directly.

## Standard delegation cycle

See the [canonical delegation cycle in `docs/ORCHESTRATOR.md`](../../docs/ORCHESTRATOR.md#cmux-delegation-cycle) for the full worktree→spawn→dispatch→poll→verify→merge→cleanup flow. After dispatch, the orchestrator MUST enter [standby mode](../../docs/ORCHESTRATOR.md#standby-after-dispatch) — no active screen polling, no typing into the agent pane until completion signal or user nudge. The per-script reference above documents each script's interface in detail. The bash example has been removed to avoid drift — refer to the canonical doc instead.

## Conventions (encoded in the scripts)

- **Worktrees** branch off `origin/main` by default (override via `BASE_REF` env
  or `verify.sh`'s `[base-ref]` arg), live as siblings of the repo
  (`../wt-<task>`), carry `.env`/`.env.local` if present, and get their own
  dependency install only when a `package.json` exists.
- **Rock-band tab names** are auto-assigned by `agent-spawn.sh` via `pick_band`
  — a random band from the pool that is not already a live tab title, so names
  never repeat across concurrent agents and you never pick one by hand.
- **Hard gate before merge**: run `verify.sh` (or `verify-ts.sh` for TS projects).
  Never merge on the agent's self-report.
- **Model tiers** are config-driven via `.tasks/config.json` (see `bin/board-config --get-model <tier>`).
  Five tiers are defined — `flash` (mechanical), `pro` (reasoning), `review`, `simple`, and `top` —
  each mapped to a model id in the config or falling back to built-in defaults.
  Pass the tier name directly as the `<model>` arg to `agent-spawn.sh`; it resolves
  automatically. Raw model ids still work unchanged.



## Live-deploy traps (wrangler 4.x) — why mocks aren't enough

- **`kv key put/get` defaults to LOCAL simulation.** Without `--remote` it never
  touches production KV. A publish command that mocks `spawnWrangler` will pass
  its unit tests while writing nothing live. Always verify with
  `wrangler kv key get <k> --namespace-id <id> --remote` and a real `curl`.
- **`init`/`deploy` must wire the real `kv_namespace_id` into `wrangler.jsonc`.**
  A placeholder id deploys a Worker whose binding resolves to nothing → endpoint
  404s even though the key exists. Check the deploy output's bindings table.
- After any agent's "publish/deploy" feature: do the real `wrangler deploy` +
  `--remote` write + `curl` yourself before declaring it working.
