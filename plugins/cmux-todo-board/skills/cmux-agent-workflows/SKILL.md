---
name: cmux-agent-workflows
description: Advanced cmux agent orchestration helpers — on-demand / advanced only. Covers agent backends, hook installation, codex gotchas, live-deploy traps, and detailed script implementation.
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

The default worker runtime is `pi`, launched headlessly in the target worktree.

```bash
worker-spawn.sh <worktree> --profile <name> [label]
worker-spawn.sh <worktree> <provider/model> [label]
```

- `worker-spawn.sh` backgrounds `pi -p --mode json -a`, writes `out.json`, and prints the PID.
- Completion is the worker process exit code + a new commit on the branch (git progress) + the worker's branch commit.
- `worker-watch.sh --pid <PID> --out <WT>/out.json --worktree <WT>` is the canonical waiter / liveness watchdog.

## Scripts (in `scripts/`)

| Script | Purpose | Example |
|---|---|---|
| `wt-new.sh <branch> <dir>` | New worktree (base overridable via `BASE_REF` env) + copy `.env` if present + `bun install` only if `package.json` exists | `wt-new.sh feat/foo ../wt-feat-foo` |
| `worker-spawn.sh <worktree> [--profile <name>] [label]` | Start a headless `pi` worker and echo the PID | `worker-spawn.sh $WT --profile backend 151` |
| `worker-watch.sh --pid <PID> --out <WT>/out.json --worktree <WT>` | Canonical waiter / liveness watchdog for headless `pi` workers | `worker-watch.sh --pid $PID --out $WT/out.json --worktree $WT` |
| `verify.sh <wt> [base-ref]` | Project-agnostic gate: `bash -n` on changed shell scripts + `bun test`/`npm test` if a test script exists; no-op otherwise | `verify.sh $WT` |
| TS hard-gate helper | archived in legacy-reference; use the current project verification flow | `verify.sh ../wt-feat-foo` |
| `pr-finish.sh <pr#> [wt]` | Remove worktree, squash-merge, delete branch | `pr-finish.sh 121 $WT` |

`lib.sh` is shared (sourced by the others): `cmux_surfaces`, `cmux_tty`,
`agent_kind_detect`, `agent_launch_cmd`, `agent_ready_patterns`,
`agent_kill_pattern`, `wait_agent_ready`. Not run directly.

## Standard delegation cycle

See the [canonical delegation cycle in `docs/ORCHESTRATOR.md`](../../docs/ORCHESTRATOR.md#headless-delegation-cycle) for the full worktree→headless-pi→dispatch→standby→verify→merge flow. After dispatch, the orchestrator MUST enter [standby mode](../../docs/ORCHESTRATOR.md#standby-after-dispatch) — wait on the worker process exit code, a new commit on the branch (git progress), and the branch commit. The per-script reference above documents each script's interface in detail.

## Conventions (encoded in the scripts)

- **Worktrees** branch off `origin/main` by default (override via `BASE_REF` env
  or `verify.sh`'s `[base-ref]` arg), live as siblings of the repo
  (`../wt-<task>`), carry `.env`/`.env.local` if present, and get their own
  dependency install only when a `package.json` exists.
- **Hard gate before merge**: run `verify.sh`; TS projects use the archived legacy-reference helper.
  Never merge on the worker's self-report.
- **Model profiles** are config-driven via `.tasks/config.json` (see `bin/board-config --get-profile <name>`).
  Profiles are defined for each role — `backend`, `backend-fast`, `docs`, `review`, `test`, `tiny-patch`,
  `repo-scout`, `frontend`, `frontend-top` — each carrying the full Pi launch contract (provider, model,
  thinking, tools). Resolve the profile values into the canonical headless `pi -p` launch.




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
