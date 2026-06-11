# Orchestrator Token Efficiency — Research Spike (Wave 2)

**Date:** 2026-06-11
**Status:** DESIGN SPIKE (no behavioral changes)
**Builds on:** commit `44c75a5` — feat(#42): token-efficiency pass — 7 changes

---

## 0. What #42 already accomplished (do not repeat)

| # | Change | Mechanism | Status |
|---|--------|-----------|--------|
| 1 | `board-pull` omits `body` from default `--json` fields | `--with-body` flag gates full-body inclusion | DONE |
| 2 | `board-render`: `body_preview` (200 chars) + `body_sha` in `board.json` | Only `ready` issues get per-issue `.md` files | DONE |
| 3 | `board-render-body <N>` | On-demand full-body retrieval from cache or `gh issue view` | DONE |
| 4 | `board-onboard-lite` | Compact 52-line bootstrap; full rules in `docs/ORCHESTRATOR.md` (lazy-loaded) | DONE |
| 5 | `board-plan`: cap mirrored ready at 5 | `… and N more` summary line for overflow | DONE |
| 6 | `board-run-ready`: compact `.task-spec.md` | In-worktree spec format with `forbidden_reads` guard | DONE |
| 7 | `forbidden_reads` in `.task-spec.md` | Forbids glob-read of `.tasks/issues/*` to prevent body leakage | DONE |

---

## 1. Hotspot Inventory

### 1.1 Skill instruction inflation (per clean session)

Every clean orchestrator session loads at least two skills that inflate into the context window.

| Skill/Doc | Size (bytes) | Lines | Loaded when | Notes |
|-----------|-------------|-------|-------------|-------|
| `skills/board-onboard/SKILL.md` | 5,151 | 101 | Full onboard (`/board-onboard`) | MEASURED via `wc -c` |
| `skills/board-onboard-lite/SKILL.md` | 1,889 | 52 | Lite onboard (`/board-onboard-lite`) | MEASURED via `wc -c` |
| `skills/cmux-agent-workflows/SKILL.md` | 9,727 | 143 | Every session (loaded as available skill) | MEASURED via `wc -c` |
| `docs/ORCHESTRATOR.md` | 5,848 | 129 | On-demand (referenced by lite, not auto-loaded) | MEASURED via `wc -c` |
| **Total (lite path)** | **11,616** | — | Per clean session | Sum of lite + cmux skill |

**Finding:** `cmux-agent-workflows/SKILL.md` is the single largest instruction surface at 9,727 bytes — nearly 5x the size of `board-onboard-lite`. It is loaded as an available skill every session even though it is purely reference material (script catalog, conventions, gotchas). The orchestrator only needs the delegation cycle summary and script names; all other content (live-deploy traps, codex gotchas, MCP warnings, rock-band naming mechanics) is consumed at most once.

### 1.2 `board.json` full read (per round)

The orchestrator reads `.tasks/board.json` at each round's "On invocation" step to summarize counts and run `board-plan`.

| Board size | Est. bytes (JSON) | Loaded per round | Notes |
|-----------|-------------------|-----------------|-------|
| 5 issues | ~2,500 | Every round | MEASURED — simulated via Python |
| 15 issues | ~7,700 | Every round | Typical active project |
| 50 issues | ~25,500 | Every round | Large project |

**Finding:** Reading full `board.json` when only status counts + next-ready are needed burns ~50x more tokens than necessary. The `board-status` helper already produces a compact ~150-byte summary. The only step that genuinely needs the full board is `board-plan` (to extract ready task titles + URLs for mirroring). The orchestrator's initial summary step (step 3: "summarize counts per status") does not need the full file.

### 1.3 Agent screen polling (per spawn)

`agent-spawn.sh` calls `wait_agent_ready()` from `lib.sh`, which polls `cmux read-screen --surface <s> --lines 40` every 3 seconds until the agent TUI shows a readiness banner (up to 120s timeout).

| Variable | Value | Notes |
|----------|-------|-------|
| Lines per screen read | 40 | Hardcoded in `wait_agent_ready` (`lib.sh:150`) |
| Poll interval | 3s | Hardcoded (`lib.sh:164`) |
| Max reads per spawn | ~40 | 120s / 3s |
| Output per read (est.) | 2,000–5,000 chars | ANSI escape sequences, TUI borders, prompt text |
| **Total per spawn** | **80–200 KB** of screen output | ASSUMED (depends on terminal width, model banner) |

**Finding:** Each `cmux read-screen` call produces terminal output that enters the orchestrator's context when run via Bash tool. At 3s intervals over a 120s window, up to 40 reads occur — even if the agent is ready in 15s, that's still 5 reads × 40 lines = ~10-25 KB of noise. This is the largest single source of recurring token waste in the dispatch loop. The readiness check could be done entirely inside the background script (not surfaced to orchestrator context) or via event-driven signaling instead of screen polling.

### 1.4 `poll-wait.sh` background chatter

When run via `Bash run_in_background:true`, the script produces log lines and final output that are surfaced to the orchestrator as background notifications.

| Output source | Est. chars | Notes |
|--------------|-----------|-------|
| `log()` stderr lines | ~100–200 | "baseline for <branch>", "agent kind", etc. (lib.sh `log()`) |
| `cmux events | grep` startup | ~50 | Binary output may still trigger relay |
| Final COMPLETE/TIMEOUT line | ~80 | One line on completion |
| `poll-push.sh` fallback `log()` | ~100 | If event path disabled or falls through |
| **Total background noise** | **200–500 chars** per dispatch | MEASURED (script source analysis of log calls) |

**Finding:** Low individual cost, but accumulates across N parallel dispatches. The `log()` helper in `lib.sh` unconditionally emits to stderr via `echo ">> $*" >&2`. In a background Bash invocation, stderr is captured and surfaced. A `--quiet` flag or `log()` that no-ops unless `DEBUG=1` would eliminate this entirely.

### 1.5 `board-pull` command output

| Output | Est. size | Notes |
|--------|----------|-------|
| `board-render` summary (stderr) | ~100 chars | "X tasks → .tasks/board.json + TODO.md (ready=N, ...)" |
| `board-pull` final summary (stdout) | ~150 chars | "Pulled N issues | ready=X blocked=Y" |
| **Total** | **~250 chars** | Already minimal |

**Finding:** Already efficient. Low priority.

### 1.6 SessionStart hook output

`hooks/hooks.json` runs a `grep -c` pipeline every session start, producing ~3 lines of output.

| Output | Est. chars | Notes |
|--------|----------|-------|
| `grep -c '^## '` + `grep -c '^- \[ \]'` | ~50 chars | Status sections + open checkbox counts |
| **Total** | **~50 chars** | Negligible |

**Finding:** Already minimal. Could be replaced with a single `board-status` call for richer data at same cost, but not a meaningful saving.

### 1.7 Instruction duplication across skills

| Duplicate topic | Appears in | Overlap |
|----------------|-----------|---------|
| Role: ORCHESTRATOR, delegate coding | `board-onboard`, `docs/ORCHESTRATOR.md` | ~20 lines nearly identical |
| State model (sources of truth) | `board-onboard`, `docs/ORCHESTRATOR.md`, `board-onboard-lite` | Same canonical status order, same 4 sources |
| Board workflow table | `board-onboard`, `docs/ORCHESTRATOR.md`, `board-onboard-lite` | Same 4-step table |
| Delegation cycle steps | `board-onboard`, `docs/ORCHESTRATOR.md`, `board-onboard-lite`, `board-run-ready`, `cmux-agent-workflows/SKILL.md` | Script names repeated in 5 files |
| cmux dispatch steps 1-9 | `docs/ORCHESTRATOR.md`, `board-run-ready/SKILL.md` | Same numbered list |

**Finding:** The delegation cycle is described in 5 different instruction files with varying verbosity. Each file that the orchestrator "loads" or "reads" adds to context. Consolidating the cycle into one canonical reference (already partially done via `docs/ORCHESTRATOR.md`) and having all skills link to it would cut ~1-2 KB of redundancy per session.

---

## 2. Reduction Proposals (ranked by saving × safety)

### Proposal 1: `cmux-agent-workflows-lite` skill (or inline compaction)

**What:** Create a compact variant of `cmux-agent-workflows/SKILL.md` (~1,500 bytes) that only contains the delegation cycle summary, script names, and a link to the full reference. Mirror the `board-onboard` / `board-onboard-lite` pattern.

**Est. saving:** 6,000–8,000 bytes per clean session (ASSUMED — based on diff between current 9,727 bytes and target ~2,000 bytes)

**Risk:** LOW. Does not touch any scripts or behavioral code. The full SKILL.md remains available for first-time setup or manual reference. The orchestrator uses the lite path by default, identical to the `board-onboard-lite` precedent.

**Touches correctness:** No. Purely instruction surface compaction.

**Precedent:** #42 change 4 (`board-onboard-lite`) with identical architecture.

### Proposal 2: `board-status` for round summary instead of full `board.json` read

**What:** Modify the "On invocation" step in board-onboard/board-onboard-lite/ORCHESTRATOR.md to use `bin/board-status` (150 bytes output) instead of reading the full `.tasks/board.json` (7–25 KB). Keep the full read only for `board-plan` (which needs title/URL data for task mirroring). This is a *behavior change in instructions*, not code.

**Est. saving:** 7,000–25,000 bytes per round (MEASURED — simulated JSON size minus board-status output size)

**Risk:** LOW-MEDIUM. The orchestrator's initial summary needs counts per status + next-ready. `board-status` already provides both. If the orchestrator also needs to inspect specific issue details (e.g., labels, assignees for filtering), it can read individual entries from `board.json` on demand. The risk is that some orchestrator decisions were implicitly relying on seeing all entries in context.

**Touches correctness:** Possibly. The orchestrator currently sees the full board and may use that context for decisions. Mitigation: run `board-status` first for counts, then selectively read `board.json` entries only for ready tasks that will be dispatched.

**Precedent:** #42 change 5 already capped board-plan mirroring at 5. This extends the "don't load everything" pattern to the initial summary step.

### Proposal 3: Move agent readiness polling out of orchestrator context

**What:** `agent-spawn.sh` currently runs `wait_agent_ready()` synchronously inside the spawn command, which means all `cmux read-screen` output enters orchestrator context. Instead: make `agent-spawn.sh` fire-and-forget the readiness check, return the surface ref immediately, and have the orchestrator use `poll-wait.sh` (which already uses event-driven waiting) to confirm readiness. The screen polling stays inside the script's process group and is never surfaced.

**Est. saving:** 10,000–200,000 bytes per dispatch (ASSUMED — based on 5–40 screen reads × 2–5 KB each, depending on how quickly the agent boots)

**Risk:** MEDIUM. Changes the orchestrator's dispatch flow: currently the orchestrator spawns an agent and blocks until it sees the surface ref indicating readiness. With this change, the orchestrator spawns, gets a surface ref immediately, then sends the task spec and polls for completion. If the agent isn't ready when `agent-send.sh` fires, the typed text may land in the agent's startup sequence (before the prompt is active). Mitigation: `agent-send.sh` could poll readiness itself (inside the script, not surfaced to orchestrator) before sending.

**Touches correctness:** Yes. Requires changes to `agent-spawn.sh` to detach readiness polling, and to `agent-send.sh` to wait-for-ready before typing. The behavioral change is in the scripts, not in the orchestrator's decision-making.

**Precedent:** `poll-wait.sh` already moved waiting from polling to event-driven. This extends the same principle to the spawn phase.

### Proposal 4: `--quiet` flag for background scripts

**What:** Add a `--quiet` flag (or `LOG_LEVEL` env var) to `lib.sh`'s `log()` function so background scripts (`poll-wait.sh`, `poll-push.sh`, `agent-spawn.sh`) suppress stderr chatter when run via `Bash run_in_background:true`. Default behavior unchanged; the orchestrator explicitly passes `--quiet`.

**Est. saving:** 200–500 bytes per dispatch × N concurrent agents (ASSUMED — based on log call count in scripts)

**Risk:** LOW. Only affects stderr output; final COMPLETE/TIMEOUT lines still go to stdout for the orchestrator to capture. Debugging is preserved via explicit `--verbose` or `LOG_LEVEL=debug`.

**Touches correctness:** No. Purely output formatting.

### Proposal 5: Consolidate delegation cycle into single canonical source

**What:** Reduce the delegation cycle description to a single canonical location (preferably `docs/ORCHESTRATOR.md` already serves this role). All 5 skill files that reference it should link instead of inlining. Specifically:
- `board-run-ready/SKILL.md` (lines 63-71): replace the numbered 1-9 steps with a link to `docs/ORCHESTRATOR.md#cmux-delegation-cycle`
- `board-onboard/SKILL.md` (lines 73-90): already summarized; no change needed
- `board-onboard-lite/SKILL.md` (lines 40-44): keep the compact one-liner format
- `cmux-agent-workflows/SKILL.md` (lines 80-98): the "Standard delegation cycle" bash block duplicates `board-run-ready`

**Est. saving:** 1,000–2,000 bytes per session (ASSUMED — based on duplicative lines across files)

**Risk:** LOW. No behavioral change. Skills already reference `docs/ORCHESTRATOR.md`.

**Touches correctness:** No. Instruction deduplication only.

### Proposal 6: `TODO.md` read avoidance

**What:** The orchestrator currently reads `TODO.md` as a read-only render. The SessionStart hook also runs `grep` on it. Since `board.json` + `board-status` + `board-next` provide all the same information in machine-readable form, the orchestrator never needs the human-readable `TODO.md`. Remove references to reading `TODO.md` from the invocation steps.

**Est. saving:** 2,000–10,000 bytes per round (MEASURED — TODO.md size mirrors board.json minus JSON structure overhead)

**Risk:** LOW. `TODO.md` remains generated as a human reference but the orchestrator never loads it into context. The SessionStart hook could switch from `grep TODO.md` to just echoing nothing or using `board-status`.

**Touches correctness:** No. The orchestrator's decisions are based on `board.json`, not `TODO.md`.

### Proposal 7: Compress `docs/ORCHESTRATOR.md` with symbol compression

**What:** If the orchestrator does need to load full rules (e.g. first-time onboard), apply symbol compression to `docs/ORCHESTRATOR.md`: replace verbose English with keyword-dense format (abbreviations, bullet-only, remove articles). This is a docs-only change — the orchestration logic is preserved.

**Example:** "Never merge on an agent's self-report. Run the hard gate yourself" → "Never merge on self-report. Run hard gate yourself (tests + validate)."

**Est. saving:** 1,000–2,000 bytes (ASSUMED — 20-30% reduction on 5,848 bytes)

**Risk:** LOW. Only affects the reference document, not the inline skill instructions.

**Touches correctness:** No.

---

## 3. Measurement Plan

### 3.1 Before/after methodology

For each proposal implemented, measure:

1. **Raw file size:** `wc -c` on instruction files (SKILL.md, docs) before and after.
2. **Round-trip token estimate:** Sum of file sizes loaded per orchestrator round (skills + board.json + command outputs). Compare before/after.
3. **Actual token count (if available):** Use the orchestrator's session token counter or model API response metadata for empirical measurement.

### 3.2 Instrumentation checklist

| Measurement | Tool | Baseline | Notes |
|------------|------|----------|-------|
| Skill SKILL.md sizes | `wc -c skills/*/SKILL.md` | This document §1.1 | Re-run after each change |
| board.json size (simulated) | Python JSON dump | This document §1.2 | Test with 5/15/50 issue fixtures |
| board-status output size | `board-status | wc -c` | ~150 bytes | Already compact |
| agent screen read size | `cmux read-screen --lines 40 | wc -c` | 2-5 KB | Need live measurement |
| poll-wait background output | `wc -c` of captured stderr | This document §1.4 | Re-run with --quiet flag |
| Round-trip total | Sum of all loaded artifacts | This document summary | Recompute per proposal |

### 3.3 Test fixtures

Create standardized test fixtures for:
- **Small board:** 5 GitHub issues (1 ready, 2 inbox, 1 in-progress, 1 blocked)
- **Medium board:** 15 issues (5 ready, 5 inbox, 3 in-progress, 2 blocked)
- **Large board:** 50 issues (15 ready, 20 inbox, 10 in-progress, 5 blocked)

Use these as fixed inputs when measuring board.json/TODO.md/board-status output sizes.

### 3.4 Verification gates

- `claude plugin validate .` must pass (no behavioral changes to plugin)
- Existing tests in `tests/` must still pass (if proposals touch scripts)
- Measurement deltas must be documentable: "Proposal N reduced per-round tokens from X to Y"

---

## 4. Open Questions / Decisions

### Q1: Should `cmux-agent-workflows-lite` be the new default?

Currently `board-onboard-lite` exists as an alternative to `board-onboard`. Should the cmux workflows skill follow the same pattern (full + lite) or should the existing `SKILL.md` be compacted directly? The lite pattern preserves backward compatibility for users who want the full reference in-session.

**Recommendation:** Create `cmux-agent-workflows-lite` mirroring the `board-onboard-lite` pattern. The orchestrator's "On invocation" steps should direct to the lite skill. Full skill remains for first-time setup.

### Q2: Can the orchestrator use `board-status --json` for ALL board data access?

Currently the orchestrator reads `board.json` directly. `board-status --json` returns counts + next-ready as a compact JSON object. For `board-plan` mirroring, the orchestrator still needs to iterate ready tasks. Could `board-status --json` be extended with a `--ready-tasks` flag that returns just the 5 ready tasks needed for mirroring, avoiding the full `board.json` read?

**Recommendation:** Yes. Add `--ready-tasks N` to `board-status --json` that returns counts + up to N ready task objects (title, number, url, labels). This replaces both the summary step AND the board-plan input with a single compact call (~1-2 KB instead of 7-25 KB).

### Q3: Is the agent readiness screen polling actually a problem in practice?

The 10-200 KB estimate assumes every `cmux read-screen` call surfaces output to the orchestrator context. If the Bash tool only relays the final exit code/output of `agent-spawn.sh` (which echoes the surface ref at the end), the screen reads within `wait_agent_ready` may not pollute context. This needs empirical verification: run `agent-spawn.sh` via the orchestrator's Bash tool and measure how much output enters context.

**Recommendation:** Measure before implementing. If the Bash tool only captures the final stdout (surface ref), Proposal 3 is moot. If it captures all `cmux read-screen` output from the subshell, it's the highest-priority fix.

### Q4: Should the SessionStart hook be removed entirely?

The hook currently prints a 3-line board summary on every session start. With the orchestrator running `board-status` explicitly in its invocation step, the hook output is redundant. Removing it saves negligible tokens (~50 bytes) but eliminates a duplicate data source.

**Recommendation:** Low priority. Keep as-is unless consolidating all board access patterns into `board-status`.

### Q5: What is the orchestrator's actual "round" frequency?

The savings estimates assume:
- **Per session:** Skill loading cost (once)
- **Per round:** board.json read, board-plan, board-status (repeated)

If the orchestrator runs many rounds per session, per-round savings dominate. If sessions are short and single-round, the skill loading cost dominates.

**Recommendation:** Profile a typical orchestration session to determine round count. This determines whether Proposal 1 (per-session) or Proposal 2 (per-round) is higher effective priority.

---

## 5. Summary: Priority Matrix

| # | Proposal | Saving (est.) | Risk | Per-session or per-round | Effort |
|---|----------|--------------|------|--------------------------|--------|
| 1 | `cmux-agent-workflows-lite` | 6-8 KB | LOW | Per session | LOW (new SKILL.md) |
| 2 | `board-status` over `board.json` read | 7-25 KB | LOW-MED | Per round | MEDIUM (instruction change) |
| 3 | Detach agent readiness polling | 10-200 KB | MEDIUM | Per dispatch | MEDIUM-HIGH (script changes) |
| 4 | `--quiet` flag for bg scripts | 0.2-0.5 KB | LOW | Per dispatch | LOW (lib.sh change) |
| 5 | Deduplicate delegation cycle | 1-2 KB | LOW | Per session | LOW (doc edits) |
| 6 | Avoid `TODO.md` read | 2-10 KB | LOW | Per round | LOW (instruction change) |
| 7 | Symbol-compress `ORCHESTRATOR.md` | 1-2 KB | LOW | Per session (if loaded) | LOW (doc edit) |

**Recommended implementation order:** 1 → 2 → 4 → 6 → 5 → 3 → 7

Proposals 1, 5, and 7 are pure documentation/instruction changes with zero correctness risk. Proposals 2 and 6 are instruction changes that affect orchestrator behavior (what it reads). Proposal 4 is a script output change. Proposal 3 is a script behavioral change that needs empirical measurement first (see Q3).

**Total estimated savings (all proposals):** 15-45 KB per round + 8-12 KB per session
