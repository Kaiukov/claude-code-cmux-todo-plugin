---
name: cmux-agent-workflows
description: Advanced cmux agent orchestration helpers — on-demand / advanced only. Covers agent backends, hook installation, codex gotchas, live-deploy traps, and detailed script implementation. For routine delegation, use cmux-agent-workflows-lite.
---

# cmux agent workflows

Token-saving shell helpers for the orchestrator pattern: the main agent (Opus)
delegates ALL coding to headless `pi` workers, then independently verifies and merges.
Each script replaces a multi-call shell sequence I would otherwise type by hand.

**Live deploy / KV writes / DB mutations stay orchestrator-only.** Agents
implement and unit-test on MOCKS; the orchestrator runs the single real
`wrangler deploy` / `kv key put --remote` / migration. Mocks pass while live
breaks — always do the live check yourself (see the `--remote` and
KV-binding traps below).

## Primary dispatch path

The default worker runtime is `pi`, launched headlessly in the target worktree via the canonical shape:

```bash
cd <worktree> && pi -p --mode json -a \
  --provider <p> --model <m> --tools <...> \
  --append-system-prompt prompts/pi/roles/<role>.md @<worktree>/.task-spec.md > out.json 2>&1 &
```

- `-a` keeps trust per run; it does not mutate global `~/.pi/agent/trust.json`.
- Completion is the worker process exit code + `CTB-DONE` in output + the worker's branch commit.
- The 3×3 cmux cockpit is parked as an optional live dashboard for watch/intervene only.

## Scripts (in `scripts/`)

| Script | Purpose | Example |
|---|---|---|
| `wt-new.sh <branch> <dir>` | New worktree (base overridable via `BASE_REF` env) + copy `.env` if present + `bun install` only if `package.json` exists | `wt-new.sh feat/foo ../wt-feat-foo` |
| `verify.sh <wt> [base-ref]` | Project-agnostic gate: `bash -n` on changed shell scripts + `bun test`/`npm test` if a test script exists; no-op otherwise | `verify.sh $WT` |
| `verify-ts.sh <wt>` | TS-specific hard gate: typecheck + full `bun test`, exits non-zero on any failure | `verify-ts.sh ../wt-feat-foo` |
| `pr-finish.sh <pr#> [wt]` | Remove worktree, squash-merge, delete branch | `pr-finish.sh 121 $WT` |
| `agent-spawn.sh <dir> <wt> <model> [label] [extra agent args...] [--agent pi]` | Legacy / optional-dashboard worker surface helper (not the default path) | `agent-spawn.sh right $WT opencode-go/deepseek-v4-pro TASK` |
| `agent-send.sh <surface> <text…>` | Legacy / optional-dashboard prompt helper | `agent-send.sh surface:172 "run tests, paste output"` |
| `agent-screen.sh <surface> [lines]` | Legacy / optional-dashboard screen read | `agent-screen.sh surface:172 30` |
| `agent-kill.sh <surface> [--agent pi] [--close]` | Legacy / optional-dashboard cleanup helper | `agent-kill.sh surface:172 --agent pi --close` |
| `agent-notify.sh --task <id> --surface <ref> --status success\|failure [--branch <b>]` | Legacy / optional-dashboard CTB-DONE helper | `agent-notify.sh --task 32 --surface surface:172 --status success --branch feat/foo` |
| `poll-wait.sh --surface <ref> --branch <name> [--task <id>] [--event-timeout <s>] [--total-timeout <s>]` | Legacy / optional-dashboard waiter | `poll-wait.sh --surface surface:172 --branch feat/foo --task 44 --total-timeout 600` |
| `poll-push.sh <branch> [int] [timeout]` | Legacy / optional-dashboard git-poll fallback | `poll-push.sh feat/foo 30 1800` |

`lib.sh` is shared (sourced by the others): `cmux_surfaces`, `cmux_tty`,
`pick_band` (random rock-band name excluding live tabs), and the
agent-dispatch helpers `agent_kind_detect`, `agent_launch_cmd`,
`agent_ready_patterns`, `agent_kill_pattern`, `wait_agent_ready`. Not run
directly.

## Standard delegation cycle

See the [canonical delegation cycle in `docs/ORCHESTRATOR.md`](../../docs/ORCHESTRATOR.md#headless-delegation-cycle) for the full worktree→headless-pi→dispatch→standby→verify→merge→cleanup flow. After dispatch, the orchestrator MUST enter [standby mode](../../docs/ORCHESTRATOR.md#standby-after-dispatch) — wait on the worker process exit code, the `CTB-DONE` sentinel, and the branch commit; no active polling or typing into the optional dashboard. The per-script reference above documents each script's interface in detail. The bash example has been removed to avoid drift — refer to the canonical doc instead.

## Conventions (encoded in the scripts)

- **Worktrees** branch off `origin/main` by default (override via `BASE_REF` env
  or `verify.sh`'s `[base-ref]` arg), live as siblings of the repo
  (`../wt-<task>`), carry `.env`/`.env.local` if present, and get their own
  dependency install only when a `package.json` exists.
- **Rock-band tab names** are auto-assigned by `agent-spawn.sh` when you use the
  parked dashboard; the random band from the pool is not already a live tab
  title, so names never repeat across concurrent optional surfaces.
- **Hard gate before merge**: run `verify.sh` (or `verify-ts.sh` for TS projects).
  Never merge on the worker's self-report.
- **Model profiles** are config-driven via `.tasks/config.json` (see `bin/board-config --get-profile <name>`).
  Profiles are defined for each role — `backend`, `backend-fast`, `docs`, `review`, `test`, `tiny-patch`,
  `repo-scout`, `frontend`, `frontend-top` — each carrying the full Pi launch contract (provider, model,
  thinking, tools). Resolve the profile values into the canonical headless `pi -p` launch; the parked dashboard
  helpers remain optional only.




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
