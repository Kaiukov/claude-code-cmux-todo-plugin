# Orchestrator Token-Efficiency Policy

Canonical reference for orchestrator token-efficiency rules. Loaded via link from
`docs/ORCHESTRATOR.md`. Kept separate so the orchestrator doc stays lean and
the policy doc can be loaded on demand.

---

## A — Behavioral rules

One line each; every orchestrator turn must honour every rule.

- **fresh-task** — `/clear` or start a fresh session when switching to an unrelated issue; do not accumulate state across issues.
- **one-goal** — never combine research + implementation + 5 merges + cleanup in a single turn. One goal per turn.
- **delegation-first** — tactical (functions, tests, refactor) and mechanical (formatting, rename, boilerplate, config/JSON) work → delegate to workers. Keep only strategic work.
- **bounded-discovery** — read only the files and functions needed for the spec at hand. No exploratory full-project reads.
- **standby** — after dispatching a worker, do not poll the worker pane. Wait for the completion signal or a user nudge. See `ORCHESTRATOR.md#standby-after-dispatch`.
- **targeted-verification** — verify only changed files, their tests, and acceptance criteria. Do not re-read everything the worker read.
- **compact-report** — end every turn with a ≤20-line report summarising status, changed files, test results, and next action.

## B — Model / effort routing

| Work type | Orchestrator model/effort |
|---|---|
| Routine board status, triage, dispatch, cleanup planning | Sonnet / low–med |
| Normal review orchestration, bounded debugging | Sonnet / med |
| Complex architecture, security, cross-system failure analysis | Opus / med |
| Exceptional high-risk arch or final adversarial review | Opus / high |

**Notes:**

1. **Opus/high is NOT the default.** The default state is Sonnet/med. Escalate to
   Opus/med when the problem involves multiple subsystems, security boundaries,
   or cross-system failure modes. Escalate to Opus/high only for the most
   critical decisions (e.g. final adversarial review before a production
   release, high-risk architecture change).
2. **Operational guidance only.** This table describes *recommended* model/effort
   per work type. It does not silently override host-level model selection.
   The orchestrator may request a profile via `board-config --get-profile <name>`
   but the host/provider ultimately controls what model runs.
3. **Mechanical work → cheapest worker profile** (backend-fast/docs). Never use an
   expensive orchestrator model for mechanical tasks. Delegate formatting,
   renames, boilerplate, and config/JSON changes to `backend-fast` or `docs` workers.

## C — Tool-output budgets

Every read/inspection tool call must minimise output size. Rules:

| Rule | Detail |
|---|---|
| **Max direct read** | Default ≤120 lines. If more is needed, use targeted ranges. |
| **Final worker screen** | `agent-screen.sh <surface> <N>` — N ≤ 40 lines. |
| **Target ranges** | Use `sed -n 'a,bp' <file>` or `rg -n <pattern> <file>` to extract only the lines needed. |
| **Select keys** | Use `jq '.<key>'` or `jq '{key1, key2}'` instead of reading full JSON files. |
| **Diff before full read** | Always run `git diff --stat` or `git diff --name-only` before a full `git diff`. Read the full diff only when necessary. |
| **Error-region tail** | When debugging errors, `tail -n <lines>` only the error region, not the whole log. |
| **Unknown-size files** | Check file size first (`ls -l` / `wc -l`) before reading with `cat`. Never `cat` a file without knowing its size. |
| **No repeat inspections** | Never re-run an identical inspection command unless state changed (file modified, process advanced) or the previous call failed. |

## G — Handoff template

When dispatching work to a worker agent, include a handoff block at the top of the task spec:

```
## Handoff
- **Repo:** owner/repo
- **Issue:** #N — title
- **State:** (current board status, branch name)
- **Worker:** (agent kind / model)
- **Branch+worktree:** <worktree-path> (branch: <name>)
- **Changed files:** <list of files to modify>
- **Tests:** <test files or test commands>
- **Next action:** <single concrete instruction>
- **Do-not-reload:** <paths the worker must not glob-read, e.g. .tasks/issues/*>
```

## H — Bounded task-spec template

Every `.task-spec.md` written by the orchestrator MUST follow this structure.
Do NOT embed full source files, full issue histories, research reports,
repeated global rules (link to them instead), or secrets.

```markdown
# Task: #<N> <title>
<optional one-line GitHub URL>

## Goal
<one-line summary of what to accomplish>

## Scope
- PRIMARY: <path> — <change description>
- SECONDARY (if any): <path> — <change description>
- DO NOT TOUCH: <paths / patterns that are off-limits>
- DISCOVERY LIMIT: read only files/functions listed below; no exploratory reads

## Files
- `<path>` — <create | modify | delete> — <brief purpose>

## Acceptance criteria
- [ ] <concrete, verifiable condition>
- [ ] <concrete, verifiable condition>

## Verification
- `bash <test-command>` — <expected result>

## Commit instructions
- Branch: <branch-name>
- Commit: <type>(<scope>): <description> (<issue-id>)
- Push: yes / no

## forbidden_reads
- <glob or path, e.g. .tasks/issues/*>

## Completion
When done, emit `CTB-DONE` via cmux notify or print `## DONE` as the final line.
```

## I — Compact worker completion report

When a worker finishes, the orchestrator produces a ≤20–40 line report. Format:

```
## Completion report
**Status:** ✅ success / ❌ failed / ⚠️ partial
**Branch:** <name> | **Commit:** <sha>
**PR:** #<N> (if created)
**Changed files:**
  - <path>
  - <path>
**Tests:** <name> — <N>/<N> passed | <N> failed | <N> skipped
**Unresolved risks:** <any known issues>
**Verification note:** <one-line confirmation of hard gate>
**Next:** <what the orchestrator should do next>

## DONE
```

If any section exceeds ~5 lines, store the full output to a temp file and
return the file path instead of inlining it. The header (status, branch, commit,
PR, tests summary) must always be inlined — only detailed logs go to files.

---

*Last updated: 2026-06-12. See `docs/ORCHESTRATOR.md` for the parent orchestrator rules.*
