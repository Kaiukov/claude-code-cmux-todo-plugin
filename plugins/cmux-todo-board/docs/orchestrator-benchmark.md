# Orchestrator Token-Efficiency Benchmark

**Status:** REPRODUCIBLE PROCEDURE
**Revision:** 1
**Last run:** —

---

## 1. Benchmark Procedure

This procedure measures orchestration overhead in a controlled, reproducible cycle. Follow it identically for baseline and optimized runs.

### Prerequisites

- A `cmux` session with the cmux-todo-board plugin loaded.
- An open GitHub issue in the `ready` status (or a test fixture that mimics one).
- `claude --debug-file /tmp/claude-debug.log` active for the session (captures raw API calls and tool results).
- `board-pull` has been run recently enough that `.tasks/board.json` reflects current board state.

### Step-by-step

1. **Fresh session.** Start with `/clear` to eliminate any prior conversation history. Confirm with `/usage` (expect zero or minimal tokens).

2. **Inspect issue.** Read the `.task-spec.md` for the target issue (the task spec already exists in the worktree from a prior round). Do NOT read the full GitHub issue body or `.tasks/issues/*`.

3. **Bounded reads.** Read only the files and functions required to understand the task:
   - The task spec (`.task-spec.md`).
   - One or two relevant source files, read with `offset`/`limit` (≤50 lines each).
   - Do NOT glob-read directories or entire files >10 KB.

4. **Capture pre-dispatch metrics.** Record `/usage` output and take a `/context` snapshot.

5. **Bounded task spec.** Verify the `.task-spec.md` is already in the agent's worktree. If it needs generation, produce a spec that fits in ≤60 lines (using the compact format from `ORCHESTRATOR.md`).

6. **Dispatch one worker.** Run `agent-spawn.sh` + `agent-send.sh` to dispatch exactly one agent. Note the dispatch time.

7. **Wait WITHOUT screen polling.** Run `poll-wait.sh --surface <ref> --branch <name>` in the background. Do NOT call `agent-screen.sh`, `cmux read-screen`, or any other polling command while the agent is working. The orchestrator waits on the event stream only.

8. **Verify changed files / tests.** After the agent completes, run the verification commands specified in the task spec (tests, typecheck, lint). Do NOT trust the agent's self-report — run the hard gate yourself.

9. **Capture post-dispatch metrics.** Record `/usage` output again. Note the final token counts and costs.

### Repeatability

- Run the procedure **three times** for each configuration (baseline, optimized) and record the median values.
- Use the same GitHub issue / test fixture for all runs within a comparison pair.
- Reset with `/clear` between runs.

---

## 2. Metrics to Capture

| Metric | Source | When to capture | Unit |
|--------|--------|----------------|------|
| Model + effort | `/config` or `board-config --get-profile` explicit | Pre-dispatch | e.g. `claude-sonnet-4-20250514:thinking` |
| `/usage` before | `/usage` output (prompt tokens, completion tokens, cost) | After step 3, before dispatch | tokens, USD |
| `/usage` after | `/usage` output (prompt tokens, completion tokens, cost) | After step 8 | tokens, USD |
| `/context` snapshot before | `/context` full output | After step 3, before dispatch | KB |
| Tool-call count | Count of tool-use blocks in `--debug-file` log for the dispatch round | Post-session (parse debug log) | count |
| Lines read directly by orchestrator | Sum of `offset`+`limit` from `read` tool calls in the dispatch round | Post-session (parse debug log) | lines |
| Largest single tool output | Max byte count of any single `read` or `bash` result in the dispatch round | Post-session (parse debug log) | bytes |
| Duplicate reads / commands | Count of repeated read calls on the same file or repeated bash commands with identical output | Post-session (parse debug log) | count |
| Time to dispatch | Wall-clock time from start of `agent-spawn.sh` to completion of `agent-send.sh` | During step 6 | seconds |
| Total orchestrator tokens | Sum of all prompt tokens across the dispatch round (from `--debug-file` or `/usage` delta) | Post-session | tokens |

### Log parsing hint

The `--debug-file /tmp/claude-debug.log` file contains NDJSON entries of the form:

```json
{"type":"turn","turn_type":"prompt","token_count":1234}
{"type":"tool_use","tool_name":"read","args":{...}}
{"type":"tool_result","token_count":5678,"output_preview":"..."}
```

Use `jq` to extract and sum the relevant fields:

```bash
# Total prompt tokens for a round
jq 'select(.type=="turn" and .turn_type=="prompt") | .token_count' /tmp/claude-debug.log | paste -sd+ - | bc

# Tool-call count
jq 'select(.type=="tool_use")' /tmp/claude-debug.log | wc -l
```

---

## 3. Baseline vs. Optimized Results

Fill this table per run. Copy the row for each comparison pair.

| Run | Model | Effort | `/usage` before (P/C/$) | `/usage` after (P/C/$) | Tools called | Lines read | Max tool output | Duplicates | Time to dispatch | Total orch. tokens |
|-----|-------|--------|------------------------|-----------------------|-------------|------------|----------------|------------|-----------------|-------------------|
| Baseline 1 | | | | | | | | | | |
| Baseline 2 | | | | | | | | | | |
| Baseline 3 | | | | | | | | | | |
| **Baseline median** | | | | | | | | | | |
| Optimized 1 | | | | | | | | | | |
| Optimized 2 | | | | | | | | | | |
| Optimized 3 | | | | | | | | | | |
| **Optimized median** | | | | | | | | | | |
| **Δ (opt − base)** | | | | | | | | | | |

### Header abbreviations

- **P** = prompt tokens
- **C** = completion tokens
- **$** = cost in USD
- **Lines read** = lines directly fetched by the orchestrator via `read` tool
- **Max tool output** = largest single-tool result in bytes
- **Duplicates** = repeated reads / commands with identical output
- **Time to dispatch** = seconds from spawn start to send completion
- **Total orch. tokens** = sum of all prompt + completion tokens in the dispatch round

---

## 4. Change Log

| Date | Change | Benchmark result delta |
|------|--------|----------------------|
| — | Initial baseline | — |
