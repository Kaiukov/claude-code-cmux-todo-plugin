# #34 Orchestrator weekly limit monitoring — research doc

**Status:** Research spike (no implementation)
**Date:** 2026-06-11
**Issue:** https://github.com/Kaiukov/claude-code-cmux-todo-plugin/issues/34

---

## 1. Detection — how to detect Claude Code weekly-limit exhaustion

### 1.1 Error banners printed to stderr/stdout

When the plan quota is exhausted Claude Code prints a blocking error banner and
refuses further requests. The following patterns are **VERIFIED** from official
docs ([Error reference](https://code.claude.com/docs/en/errors)) and confirmed by
hundreds of GitHub issues:

| Banner text | Limit type | VERIFIED? |
|---|---|---|
| `You've hit your session limit · resets 3:45pm` | 5-hour rolling session window | VERIFIED |
| `You've hit your weekly limit · resets Mon 12:00am` | 7-day (weekly) rolling cap | VERIFIED |
| `You've hit your Opus limit · resets 3:45pm` | Model-specific sub-limit | VERIFIED |
| `API Error: Rate limit reached` | Client-side synthetic OR per-minute ITPM throttle | VERIFIED |
| `Request rejected (429)` | API key per-minute rate limit exceeded | VERIFIED |
| `Server is temporarily limiting requests` | Short-lived capacity throttle (not quota) | VERIFIED |
| `Credit balance is too low` | Console prepaid credits exhausted | VERIFIED |

**Key finding:** for subscription-based auth (the orchestrator's auth mode), the
relevant banners are the first three (`session limit`, `weekly limit`,
`Opus limit`). The `429` and `Rate limit reached` messages are per-minute
API-level throttles that are typically retried automatically and do not indicate
weekly quota exhaustion. The `Credit balance` error is for pre-paid API-key
accounts, not subscription.

### 1.2 Exit codes

**ASSUMED:** The `claude --print` (non-interactive) process likely exits
non-zero when a blocking limit banner is hit, but the exact exit code is
**UNVERIFIED**. Claude Code's error-reference page does not document exit codes
for subscription-limit errors. The `claude --help` output shows no
`--status`/`--usage`/`--quota` flag for non-interactive quota checks.

**Recommendation:** Before implementation, run a controlled test:
```bash
claude -p "echo hello" 2>&1; echo "exit=$?"
```
to capture the exit code and stderr pattern when the weekly limit is active.

### 1.3 `x-ratelimit-*` / `anthropic-ratelimit-*` headers

**These are HTTP-level API response headers — NOT accessible from the CLI
surface.** The Anthropic API returns them on every response
([docs](https://docs.anthropic.com/en/api/rate-limits#response-headers)), but
Claude Code CLI abstracts the HTTP layer. The headers are:

- `anthropic-ratelimit-requests-remaining`
- `anthropic-ratelimit-tokens-remaining`
- `anthropic-ratelimit-input-tokens-remaining`
- `anthropic-ratelimit-output-tokens-remaining`
- `retry-after` (on 429 only)

**VERDICT: NOT accessible from the CLI.** A sidecar proxy that sits between
Claude Code and the API could capture these, but that is out of scope for a
lightweight shell solution.

### 1.4 Status line `rate_limits` field (key finding)

Since **v2.1.80** (March 2026), Claude Code passes a `rate_limits` object to
status line scripts via stdin JSON
([docs](https://code.claude.com/docs/en/statusline)). This is the **only
programmatic source of subscription quota data** available at the CLI layer.
The payload shape:

```json
{
  "rate_limits": {
    "five_hour": {
      "used_percentage": 42.3,
      "resets_at": 1774036800
    },
    "seven_day": {
      "used_percentage": 85.7,
      "resets_at": 1774580400
    }
  }
}
```

| Field | Meaning | VERIFIED? |
|---|---|---|
| `rate_limits.five_hour.used_percentage` | 5-hour rolling window usage (0–100) | VERIFIED (docs + community) |
| `rate_limits.five_hour.resets_at` | Unix epoch seconds when 5h window resets | VERIFIED |
| `rate_limits.seven_day.used_percentage` | 7-day weekly usage (0–100) — **this is the metric we need** | VERIFIED |
| `rate_limits.seven_day.resets_at` | Unix epoch seconds when 7d window resets | VERIFIED |

**Availability caveats** (VERIFIED from docs):
- Only present for Claude.ai subscribers (Pro/Max/Team/Enterprise), **not** for
  API-key-based auth.
- Each window (`five_hour`, `seven_day`) may be independently absent.
- Not available until after the first API response in the session.

**Status line mechanism:** Register a script in `~/.claude/settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/limit-monitor.sh"
  }
}
```
The script receives JSON on stdin and can extract `rate_limits.seven_day`.

### 1.5 `~/.claude/stats-cache.json` — post-hoc analytics

This local file contains aggregated usage stats computed from session JSONL
files ([VERIFIED](https://www.mintlify.com/1shanpanta/claude-analytics/reference/data-sources/stats-cache)).
It is **not** real-time — it is updated by the `/stats` command. Its schema:

```json
{
  "version": 2,
  "lastComputedDate": "2026-06-10",
  "dailyActivity": [{"date": "2026-06-10", "messageCount": 100, "sessionCount": 3, "toolCallCount": 30}],
  "modelUsage": {
    "claude-opus-4-6": { "inputTokens": 600000, "outputTokens": 2200000, ... }
  },
  "totalSessions": 205,
  "totalMessages": 27163
}
```

**Limitation:** provides aggregate historical usage, not current remaining
quota. The `rate_limits` status line field is the correct real-time source.

### 1.6 Client-side synthetic rate limits (known false-positive)

**VERIFIED** from multiple GitHub issues
([#33840](https://github.com/anthropics/claude-code/issues/33840),
[#40128](https://github.com/anthropics/claude-code/issues/40128)): Claude Code
has a client-side throttle that fires after ~4 rapid tool calls or when
estimated context × concurrency exceeds a threshold. It emits
`model: "<synthetic>", usage: {input_tokens: 0, output_tokens: 0}` — a request
that never reached the API. This can falsely trigger detection logic if we
only look for "rate limit" strings.

**Mitigation:** the monitor should look for the specific subscription-limit
banners (`You've hit your weekly limit`, `You've hit your session limit`,
`You've hit your Opus limit`) rather than generic "rate limit" strings.

### 1.7 Detection summary

| Method | Real-time? | Shows weekly%? | Accessible from shell? | Recommendation |
|---|---|---|---|---|
| Status line `rate_limits.seven_day.used_percentage` | Yes (per-response) | Yes | Yes (stdin JSON) | **PRIMARY** — the best signal |
| Error banners on stderr on limit-hit | Yes | No (only after exhaustion) | Yes | **FALLBACK** — catch when monitor missed pre-exhaustion |
| Exit code of `claude --print` | Yes | No | Yes | **SECONDARY** — triage, needs verification |
| `stats-cache.json` | No (post-hoc) | No | Yes | **NOT RECOMMENDED** for real-time monitoring |
| API response headers | Per-request | No (per-minute, not weekly) | No (CLI abstraction) | **OUT OF SCOPE** |
| Client-side synthetic throttle | N/A | N/A | N/A | **FALSE POSITIVE** — must be avoided |

---

## 2. Usage tracking — persistent weekly counter

### 2.1 Design

A JSON file under `.tasks/` that records the weekly usage snapshot and triggers
alerts. Week boundaries are calculated from the `resets_at` Unix timestamp
returned by the `rate_limits.seven_day` field.

**File:** `.tasks/limit-monitor.json`

```json
{
  "schema_version": 1,
  "paused": false,
  "last_check": "2026-06-11T10:30:00Z",
  "seven_day": {
    "used_percentage": 85.7,
    "resets_at": 1774580400,
    "resets_at_human": "2026-06-14T00:00:00Z",
    "alerted_at_thresholds": [50, 80]
  }
}
```

### 2.2 Week-boundary reset logic

The `resets_at` Unix timestamp is the authoritative reset time. The local
counter uses this to determine which "week" the data belongs to:

```
week_id = floor(resets_at / 604800)  # epoch-week identifier
```

When `resets_at` changes (the window rolled over), the `alerted_at_thresholds`
array is cleared so alerts fire again in the new week.

### 2.3 Survives restarts

The JSON file is persisted on disk under `.tasks/`. On each check:
1. Read the file.
2. Compare stored `resets_at` vs. current `resets_at`.
3. If different → week rolled over → reset thresholds.
4. Update `used_percentage`, `last_check`.
5. Write back.

---

## 3. Alerting — threshold-based

### 3.1 Threshold configuration

Hard-coded or environment-variable-driven thresholds:

| Threshold | Default | Action |
|---|---|---|
| `WARN_AT` | 80 | Log warning to stdout, write to `.tasks/limit-monitor.json` |
| `CRIT_AT` | 95 | Same as warn + `cmux notify` to orchestrator surface |

### 3.2 Alert channels (local only, no Hermes, no Telegram)

| Channel | Mechanism | When |
|---|---|---|
| stdout | `echo "WARN: weekly limit at ${X}%"` | Every check >= threshold |
| `.tasks/limit-monitor.json` | Record `alerted_at_thresholds` | Dedup: each threshold fires once per week |
| `cmux notify` | `cmux notify --title "Limit Alert" --body "... " --surface <orchestrator-surface>` | Only at CRIT threshold |

### 3.3 Dedup

Once a threshold alert fires for a given week, it is recorded in
`alerted_at_thresholds` and not re-fired until the week rolls over.

---

## 4. Integration shape — standalone `bin/` script

### 4.1 Recommended approach: standalone `bin/limit-monitor` script

**Recommendation: Standalone shell script at `bin/limit-monitor`.**

Trade-offs:

| Approach | Pros | Cons |
|---|---|---|
| **standalone `bin/` script** | Testable in isolation; no coupling to dispatch path; can be called from cron, statusline, or post-agent hook | Needs its own polling mechanism if used as a daemon |
| **Hook into orchestrator dispatch** | Automatically runs before/after agent dispatch | Tighter coupling; quota check adds latency to every dispatch; hard to run on a schedule |

The standalone script can be invoked in several ways:
1. **As a Claude Code status line command** — receives `rate_limits` on stdin
   every API response (most accurate, real-time).
2. **From a cron/scheduler** (e.g., every 30 min) — runs `claude --print` to
   trigger an API call, captures the status line JSON.
3. **From `board-next` or `board-run-ready`** as a pre-dispatch gate — checks
   threshold before dispatching a new agent.

### 4.2 Script outline

```bash
#!/usr/bin/env bash
# bin/limit-monitor — check weekly limit and alert if above threshold
set -euo pipefail

DATA_FILE=".tasks/limit-monitor.json"
WARN_AT="${LIMIT_WARN_AT:-80}"
CRIT_AT="${LIMIT_CRIT_AT:-95}"

# 1. Get rate_limits JSON (from stdin if piped, or by calling claude --print)
if [[ ! -t 0 ]]; then
  INPUT=$(cat)
else
  # Fallback: run a quick claude --print to trigger status line emission
  INPUT=$(claude -p "ok" --output-format stream-json 2>/dev/null | ...)
fi

SEVEN_DAY=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // empty')
RESETS_AT=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // empty')

# ... threshold check, dedup, cmux notify ...
```

### 4.3 Primary vs. secondary integration

**Primary:** Run as a status line command so every API response updates the
monitor in real time. The script reads stdin and writes `.tasks/limit-monitor.json`.

**Secondary:** A polling wrapper that runs `claude --print` periodically if the
status line integration is not viable.

---

## 5. Open questions

### 5.1 What is the actual weekly limit value?

**UNKNOWN.** Anthropic does not publish exact weekly token/call limits for
subscription plans. The `rate_limits.seven_day.used_percentage` gives us the
percentage consumed, but there is no documented `limit` value
(e.g., "1000 requests/week") accessible from the CLI. The status line field
provides `used_percentage` and `resets_at`, but **not** the absolute limit
value.

**Decision needed:** Can the orchestrator operate on percentage-only data
("used 85%") or does it need an absolute count? If percentage is sufficient
(which is the recommendation), no further work is needed.

### 5.2 Should the monitor be proactive (poll) or reactive (status line)?

The status line integration gives real-time data but only fires while a Claude
Code session is active. If the orchestrator needs to check quota before
spawning an agent (with no active session), a proactive poll is required.

**Decision needed:** Is the monitor only checked during active orchestration
sessions, or should it also run as a background check (e.g., cron) to warn when
no session is active?

### 5.3 What surface/workspace does `cmux notify` target?

For the CRIT alert, `cmux notify` needs a target surface. The orchestrator
pane's surface ref is not known at script-write time.

**Decision needed:** Should the script accept `--surface` as a parameter
(defaulting to the current workspace), or should it be configured in
`.tasks/config.json`?

### 5.4 How to handle the false-positive rate limit signals?

The client-side synthetic throttle (see §1.6) produces misleading
`API Error: Rate limit reached` messages. The monitor must be careful to match
only the subscription-limit banners (`You've hit your weekly limit`, etc.) and
not the generic "rate limit" string.

**Decision needed:** Should the detection regex be strict
(`You've hit your (weekly|session|Opus) limit`) or inclusive with a dedup
window to avoid false-positive storms?

### 5.5 What happens at 100% / post-exhaustion?

When the weekly limit is hit, any `claude` invocation is blocked with a banner.
The monitor itself (if implemented as a status line script) will stop receiving
updates because the session can no longer make API calls.

**Decision needed:** Should the polling fallback continue to check
(e.g., every 5 minutes) to detect when the limit resets, or is it acceptable
to only learn about the reset on the next successful dispatch?

### 5.6 Auth mode detection

The `rate_limits` field is only present for Claude.ai subscription auth (not
API key auth). The monitor should detect which auth mode is active and skip
checking if rate limits are not available.

**Decision needed:** Should the monitor gracefully degrade when `rate_limits`
is absent (log a warning and skip), or should it fail loudly?

---

## Appendix: References

### Official documentation
- [Claude Code Error reference](https://code.claude.com/docs/en/errors) — all
  usage-limit error banners
- [Status line docs (rate_limits)](https://code.claude.com/docs/en/statusline) —
  `rate_limits.five_hour` and `rate_limits.seven_day` fields
- [Anthropic API rate limits](https://docs.anthropic.com/en/api/rate-limits) —
  `anthropic-ratelimit-*` headers (HTTP-level, not CLI-accessible)
- [Models, usage, and limits in Claude Code](https://support.claude.com/en/articles/14552983-models-usage-and-limits-in-claude-code)
  — subscription plan limit overview
- [Claude Code usage limits explained](https://bestagent.dev/claude-code-usage-limits/)
  — community analysis of the 5-hour and 7-day windows

### Relevant GitHub issues
- [#25788](https://github.com/anthropics/claude-code/issues/25788) — session
  terminated without warning on weekly limit hit
- [#33840](https://github.com/anthropics/claude-code/issues/33840) — client-side
  synthetic rate limit (false positive with `model: "<synthetic>"`)
- [#40128](https://github.com/anthropics/claude-code/issues/40128) — rate limit
  at low usage, community diagnosis
- [#60921](https://github.com/anthropics/claude-code/issues/60921) — background
  `claude --print` silently burns quota
