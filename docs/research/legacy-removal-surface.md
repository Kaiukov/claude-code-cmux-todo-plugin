# Legacy OpenCode/Codex Worker Removal Surface

> Research for issue #98 — inventory of every place the plugin implements
> OpenCode/Codex WORKER launch/detection/readiness/kill logic.
>
> **READ-ONLY RESEARCH.** Do not remove or edit source code based on this doc.

---

## Classification guide

| Tag | Meaning |
|-----|---------|
| **REMOVE** | Worker launch/detect/ready/kill logic — goes away under Pi-only |
| **KEEP** | OpenCode/Codex as a Pi *provider* id, or as an orchestrator *host*, or historical CHANGELOG |
| **MIGRATE** | Logic that must be rewritten to the Pi path, not deleted |

---

## 1. Complete reference inventory

### 1.1 `skills/cmux-agent-workflows/scripts/lib.sh`

| Line(s) | Symbol / snippet | Class | Note |
|---------|------------------|-------|------|
| 57–60 | Comment block `# ─── Agent-kind dispatch (opencode \| codex)` | **REMOVE** | Whole dispatch section is worker logic |
| 64 | `AGENT_KINDS=(opencode codex)` | **REMOVE** | Worker-kind enum |
| 67–69 | `agent_kind_supported()` | **REMOVE** | Worker-kind validation |
| 73–87 | `agent_kind_detect()` | **REMOVE** | Auto-detect worker kind from model |
| 89–105 | `agent_launch_cmd()` | **REMOVE** | Builds `opencode --model …` / `codex --cd … -m …` |
| 113–131 | `agent_ready_patterns()` | **REMOVE** | Screen-readiness patterns per worker kind |
| 136–138 | `is_trust_prompt()` | **REMOVE** | Codex "trust this directory?" prompt detection |
| 143–166 | `wait_agent_ready()` — `kind="${2:-opencode}"`, opencode/codex branches | **REMOVE** | Worker readiness polling + trust auto-accept |
| 186–188 | `agent_kill_pattern()` — case opencode/codex | **REMOVE** | Process kill patterns per worker kind |

### 1.2 `skills/cmux-agent-workflows/scripts/agent-spawn.sh`

| Line(s) | Symbol / snippet | Class | Note |
|---------|------------------|-------|------|
| 2 | Comment: "boot an agent (opencode or codex)" | **REMOVE** | Entire file is worker spawn |
| 5 | Usage: `[--agent opencode\|codex]` | **REMOVE** | Worker kind flag |
| 7–8 | Example invocations with `--agent codex` | **REMOVE** | Worker example |
| 14 | Comment: "model_reasoning_effort=high for codex" | **REMOVE** | Codex-specific effort forwarding |
| 17–18 | Comment: model examples per kind | **REMOVE** | Worker model docs |
| 39 | Usage die message with `[--agent opencode\|codex]` | **REMOVE** | Worker kind flag |
| 42 | Comment: "model_reasoning_effort=high for codex" | **REMOVE** | Codex-specific arg |
| 73 | Comment: "opencode gateway for DeepSeek" | **REMOVE** | Worker model normalization |
| 77 | `MODEL="opencode-go/$MODEL"` | **REMOVE** | Opencode model normalization |
| 78 | `MODEL="opencode-go/${MODEL#deepseek/}"` | **REMOVE** | Opencode provider normalization |
| 94 | `command -v opencode >/dev/null` | **REMOVE** | Worker binary check |
| 95 | `command -v codex >/dev/null` | **REMOVE** | Worker binary check |
| 98–102 | `RESOLVED_EFFORT` + `AGENT_KIND == "codex"` | **REMOVE** | Codex reasoning effort forwarding |

### 1.3 `skills/cmux-agent-workflows/scripts/agent-kill.sh`

| Line(s) | Symbol / snippet | Class | Note |
|---------|------------------|-------|------|
| 5 | Usage: `[--agent opencode\|codex]` | **REMOVE** | Entire file is worker kill |
| 7 | Example: `--agent codex` | **REMOVE** | Worker example |
| 10 | Comment: "matches opencode + codex + helpers" | **REMOVE** | Worker process matching |
| 27 | Die message with `[--agent opencode\|codex]` | **REMOVE** | Worker kind flag |
| 30 | Die message usage | **REMOVE** | Worker kind flag |

### 1.4 `skills/cmux-agent-workflows/scripts/agent-send.sh`

| Line(s) | Symbol / snippet | Class | Note |
|---------|------------------|-------|------|
| 5 | Usage: `[--kind opencode\|codex]` | **REMOVE** | Worker kind flag for readiness wait |
| 7 | Example: `--kind opencode` | **REMOVE** | Worker example |
| 27 | Die message with `[--kind opencode\|codex]` | **REMOVE** | Worker kind flag |

### 1.5 `skills/cmux-agent-workflows/scripts/agent-audit.sh`

| Line(s) | Symbol / snippet | Class | Note |
|---------|------------------|-------|------|
| 54 | `printf '%s' 'opencode\|codex\|node\|bun'` | **REMOVE** | Agent process detection pattern (via `agent_kill_pattern ""`) |
| 64 | `agent_process_running()` calls `agent_kill_pattern ""` | **REMOVE** | Worker process check |
| 308 | `grep -q "opencode"` ... `grep -q "codex"` | **REMOVE** | Unit test of pattern (inline in source header) |

### 1.6 `skills/cmux-agent-workflows/scripts/poll-wait.sh`

| Line(s) | Symbol / snippet | Class | Note |
|---------|------------------|-------|------|
| 22–25 | Comments: "Codex hooks live in ~/.codex/hooks.json", "no opencode plugin files are present" | **MIGRATE** | The dual-source waiter concept lives on, but opencode/codex plugin path references must be rewritten for Pi |
| 67 | Comment: "CTB-DONE notification body... Codex completion path" | **MIGRATE** | Pi will have its own completion mechanism |

### 1.7 `bin/board-config`

| Line(s) | Symbol / snippet | Class | Note |
|---------|------------------|-------|------|
| 5 | `DEFAULT_MODELS_JSON` with `opencode/deepseek-v4-flash-free`, `opencode-go/deepseek-v4-pro` | **MIGRATE** | Default model provider prefixes change for Pi |
| 28 | `--provider` help: "Also print the provider (opencode\|codex)" | **MIGRATE** | Provider enum in CLI help changes |
| 77–82 | `auto_detect_provider()` — pattern matching for opencode/codex | **MIGRATE** | Provider detection rules change for Pi provider IDs |
| 119 | `provider="$(echo "$registry_entry" \| jq -r '.provider // "opencode"')"` | **MIGRATE** | Default provider fallback changes |

### 1.8 `bin/board-model`

| Line(s) | Symbol / snippet | Class | Note |
|---------|------------------|-------|------|
| 6 | `VALID_PROVIDERS=(opencode codex)` | **MIGRATE** | Provider enum values change for Pi |
| 12–13 | Usage: `[--provider <opencode\|codex>]` | **MIGRATE** | CLI usage text changes |
| 23–25 | Usage detail: --provider opencode or codex | **MIGRATE** | CLI usage text |
| 29 | Edit --provider: "New provider (opencode or codex)" | **MIGRATE** | CLI usage text |
| 44–45 | Validation rules: "Provider: 'opencode' or 'codex'" | **MIGRATE** | Doc text in usage |
| 159–164 | `auto_detect_provider()` — same logic as lib.sh | **MIGRATE** | Provider detection rules change for Pi |
| 430 | List command: `provider=\(.value.provider // "opencode")` | **MIGRATE** | Default provider display |
| 441 | `DEFAULT_MODELS_JSON` | **MIGRATE** | Default model provider prefixes |

### 1.9 `.opencode/` — orchestrator host (NOT worker)

| File | Line(s) | Symbol / snippet | Class | Note |
|------|---------|------------------|-------|------|
| `opencode.json` | 1–7 | Plugin manifest referencing `@opencode-ai` schema and plugin path | **KEEP** | This is the **orchestrator host** plugin manifest, not worker code |
| `plugins/cmux-board.mjs` | 1 | `import { tool } from "@opencode-ai/plugin"` | **KEEP** | SDK import for the host plugin |
| `plugins/cmux-board.mjs` | entire | Board plugin with `board_status`/`board_next`/`board_sync` tools + `session.idle` hook | **KEEP** | Orchestrator host plugin; exposes tools to the host agent |
| `package.json` | 2 | `"name": "cmux-todo-board-opencode"` | **KEEP** | Host plugin package |
| `package.json` | 6 | `"@opencode-ai/plugin": "1.17.4"` | **KEEP** | SDK dependency for host |
| `agent/orchestrator.md` | 4 | `model: opencode-go/deepseek-v4-pro` | **KEEP** | Orchestrator host config; model used by the host |
| `agent/orchestrator.md` | 37 | "Spawn agent (opencode/codex) → agent-spawn.sh" | **REMOVE** | This line references the *worker* spawn mechanism. The orchestrator.md references the worker dispatch cycle |

### 1.10 SKILL.md files

#### `skills/board-onboard-lite/SKILL.md`

| Line | Snippet | Class | Note |
|------|---------|-------|------|
| 3 | "codex trust, live-deploy traps" | **KEEP** | Skill description; references topics the skill covers (historical context) |

#### `skills/board-onboard/SKILL.md`

| Line | Snippet | Class | Note |
|------|---------|-------|------|
| 3 | "codex trust behavior, live-deploy traps" | **KEEP** | Skill description; references topics the skill covers |

#### `skills/board-model/SKILL.md`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 15, 17, 20 | `[--provider <opencode\|codex>]`, auto-detect rules | **MIGRATE** | Model skill describes provider config; enum changes for Pi |
| 43–44 | "Provider: `opencode` or `codex`." | **MIGRATE** | Provider enum doc |
| 65 | "Codex entries with reasoning_effort" | **MIGRATE** | Codex-specific dispatch docs |
| 72, 75, 82, 84, 90, 98 | Examples with `--provider codex`, auto-detect, model IDs | **MIGRATE** | Examples in skill; provider values change |

#### `skills/board-config/SKILL.md`

| Line | Snippet | Class | Note |
|------|---------|-------|------|
| 32 | `--provider` — print `opencode` or `codex` | **MIGRATE** | CLI flag doc in skill; provider enum changes |

#### `skills/cmux-agent-workflows/SKILL.md`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 3, 21, 27–28, 30, 33, 36–38, 40, 48–50, 53, 61, 64, 99, 102, 104, 106, 109–112 | All opencode/codex references | **REMOVE** | Entire skill describes the worker orchestration system (launch, hooks, gotchas) |

#### `skills/cmux-agent-workflows-lite/SKILL.md`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 3, 8 | "codex gotchas", "codex gotchas, live-deploy traps" | **REMOVE** | Lite skill references the full worker workflows |
| 38 | `agent-kill.sh "$SURF" --agent opencode --close` | **REMOVE** | Worker kill example |

#### `skills/cmux-agent-workflows/WAIT_WITHOUT_SLEEP.md`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 9, 24, 26, 29–30, 36–38, 44, 47, 50, 52, 59, 80, 138–139, 150 | All opencode/codex references | **REMOVE** | Entire doc describes opencode/codex plugin installation, agent lifecycle, and worker infrastructure |

#### `skills/cmux-agent-workflows/templates/worker-prompt.md`

| Line | Snippet | Class | Note |
|------|---------|-------|------|
| 15 | `BACKEND: codex\|opencode` | **REMOVE** | Worker prompt template references backend type |

### 1.11 Documentation

#### `docs/agent-notifications.md`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 15 | "codex (OpenAI Codex CLI)" | **REMOVE** | Notification doc section for codex worker hooks |
| 20 | "opencode" | **REMOVE** | Notification doc section for opencode worker hooks |
| 54–55 | Tables: codex and opencode hook installation | **REMOVE** | Worker-specific notification docs |

#### `docs/orchestrator-diagnostics.md`

| Line | Snippet | Class | Note |
|------|---------|-------|------|
| 4 | "orchestrator sessions powered by Claude Code, Codex, or OpenCode agents" | **KEEP** | Describes orchestrator *host* agents, not workers |

#### `docs/orchestrator-token-efficiency-research.md`

| Line | Snippet | Class | Note |
|------|---------|-------|------|
| 37 | "(live-deploy traps, codex gotchas, MCP warnings, rock-band naming mechanics)" | **MIGRATE** | Research finding listing "codex gotchas" as rarely-used content in the workflows SKILL.md; when that skill is REMOVEd, this doc needs updating |

#### `docs/ORCHESTRATOR.md`

| Line | Snippet | Class | Note |
|------|---------|-------|------|
| 60 | "Spawn agent (opencode/codex) in worktree" | **REMOVE** | Worker spawn step in the orchestrator workflow doc |

#### `docs/cmux-cheat-sheet.md`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 8 | `cmux hooks opencode install` / `cmux hooks codex install` | **MIGRATE** | Cheat sheet describes hook installation; hooks mechanism changes for Pi |
| 29–30 | Codex / OpenCode hook completion paths | **MIGRATE** | Completion mechanism changes under Pi |
| 69 | "Codex Port" link | **KEEP** | References Codex as an orchestrator host option (see codex-port.md) |

#### `docs/codex-port.md`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 1–129 | All opencode/codex references | **KEEP** | This doc describes Codex and OpenCode as **orchestrator hosts** (alternative platforms to run the board plugin), not workers. Codex port guide. |
| 64, 66, 69, 73 | Worker dispatch examples (`--agent codex`) | **MIGRATE** | The worker-spawn examples inside this doc would need updating for Pi dispatch |

#### `docs/delegation-policy.md`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 3–4 | "codex / GPT weekly budget is PAUSED", "default to opencode deepseek" | **MIGRATE** | Delegation policy references worker backends; full rewrite needed for Pi |
| 11–15 | Tier table: `opencode/deepseek-v4-flash-free`, `opencode-go/deepseek-v4-pro`, `codex gpt-5.4`, etc. | **MIGRATE** | Model tier defaults with opencode/codex prefixes change for Pi |
| 19, 21 | "Docs → flash ONLY", "pro IMPLEMENT → codex gpt-5.4 REVIEW" | **MIGRATE** | Worker backend assignments change |
| 27–28 | Model recommendations: `opencode/nemotron-3-ultra-free`, `nvidia/qwen/...` | **MIGRATE** | Model provider references change |

#### `docs/research/cmux-notify-feed-orchestrator.md`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 66, 70–71, 75–76, 79, 132, 135, 222–223, 290, 306–310, 322, 324, 326–328 | All opencode/codex references | **MIGRATE** | Research doc about opencode plugin mechanism and agent lifecycle; architecture changes for Pi |

### 1.12 Tests

#### `tests/test_agent_spawn_race.sh`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 50 | Mock read-screen: `"OpenAI Codex gpt-5-codex medium · /path"` | **REMOVE** | Codex readiness mock |
| 56–57, 61 | Mock codex binary | **REMOVE** | Worker binary mock |
| 72, 74 | `--agent codex` spawn invocations | **REMOVE** | Worker spawn test |

#### `tests/test_agent_readiness_probe.sh`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 4 | "detects the opencode TUI" | **REMOVE** | Worker readiness test |
| 11 | `FIXTURE="$SCRIPT_DIR/fixtures/opencode-narrow-pane-footer.txt"` | **REMOVE** | Opencode fixture reference |
| 27–31 | `kind="${2:-opencode}"`, opencode/codex normalization | **REMOVE** | Worker kind logic |
| 42, 52 | `agent_ready_patterns opencode`, old pattern | **REMOVE** | Worker readiness patterns |
| 71, 73 | Test 4: "Bare opencode splash" | **REMOVE** | Worker readiness test |
| 82–87, 90 | Test 5: codex readiness patterns | **REMOVE** | Worker readiness test |
| Fixture `opencode-narrow-pane-footer.txt` | entire | **REMOVE** | Opencode test fixture |

#### `tests/test_agent_audit.sh`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 54 | `printf '%s' 'opencode|codex|node|bun'` | **REMOVE** | Agent process pattern inline in test (mirrors agent-audit.sh) |
| 308 | `grep -q "opencode"` ... `grep -q "codex"` | **REMOVE** | Test asserting the kill pattern contains both opencode and codex |

#### `tests/test_opencode_bin_resolve.sh`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 1–145 | All references (`.opencode/plugins/` paths, `RUN_RESOLVE` tests) | **MIGRATE** | Tests the opencode plugin bin resolution function in `cmux-board.mjs`. Under Pi, the plugin host resolution mechanism changes. The test logic (walk-up, env override, fallback) stays conceptually valid but with Pi paths. |

#### `tests/test_poll_wait.sh`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 23 | `PLUGINDIR="$TMPENV/.config/opencode/plugins"` | **MIGRATE** | Plugin path no longer relevant under Pi |
| 126–127, 130, 132, 134, 139, 221–223 | Test C: "Codex notification wakes waiter without opencode plugin" | **MIGRATE** | The dual-source waiter concept lives on; codex/opencode plugin-specific setup changes |
| 246 | `rm -f "$TMPENV/.config/opencode/plugins/cmux-session.js"` | **MIGRATE** | Plugin path removal |

#### `tests/test_board_config.sh`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 49 | `DEFAULT_MODELS_JSON` with `opencode/deepseek-v4-flash-free`, `opencode-go/deepseek-v4-pro` | **MIGRATE** | Default model provider prefixes change |
| 188, 197 | Assertions on resolved model matching opencode prefixes | **MIGRATE** | Provider prefix assertions change |

#### `tests/test_board_model.sh`

| Line(s) | Snippet | Class | Note |
|---------|---------|-------|------|
| 21 | `VALID_PROVIDERS=(opencode codex)` | **MIGRATE** | Provider enum change |
| 91, 95–96 | `auto_detect_provider` mock and cases | **MIGRATE** | Provider detection logic change |
| 116 | `DEFAULT_MODELS_JSON` | **MIGRATE** | Default model prefixes |
| 142 | `provider="$(... jq -r '.provider // "opencode"')"` | **MIGRATE** | Default provider |
| 201–256 | Tests A9–A23: `validate_provider opencode/codex`, `auto_detect_provider` tests | **MIGRATE** | Provider validation + detection tests |
| 278–630 | Tests B–D: add/edit/delete with `--provider opencode/codex` | **MIGRATE** | Provider value tests |
| 630–632, 640–641, 682, 689, 696, 705, 714, 716, 731–732, 736, 742–743, 757, 760, 764, 766, 773–774, 776, 785, 791–794, 798, 808, 812, 826, 833–834, 838, 844, 846–847, 850 | Tests E–F: provider auto-detection, registry resolution, effort forwarding, bare model IDs | **MIGRATE** | All provider-related test assertions change for Pi |

---

## 2. Removal checklist for #98 (ordered by smallest blast radius first)

### Phase 1 — Standalone scripts (no dep from bin/ or .opencode/)

1. **`skills/cmux-agent-workflows/scripts/agent-kill.sh`** — Full file removal
2. **`skills/cmux-agent-workflows/scripts/agent-send.sh`** — Full file removal (unless the core "send text to surface" function is extracted)
3. **`skills/cmux-agent-workflows/scripts/agent-audit.sh`** — Full file removal
4. **`skills/cmux-agent-workflows/scripts/agent-spawn.sh`** — Full file removal (main worker spawn)

### Phase 2 — Library and dependent scripts

5. **`skills/cmux-agent-workflows/scripts/lib.sh`** — Remove worker dispatch functions:
   - `AGENT_KINDS`, `agent_kind_supported`, `agent_kind_detect`, `agent_launch_cmd`, `agent_ready_patterns`, `is_trust_prompt`, `wait_agent_ready`, `agent_kill_pattern`
   - Keep: `cmux_surfaces`, `cmux_tty`, `BAND_POOL`, `cmux_used_bands`, `pick_band`, `die`, `log`
   - Affects: agent-spawn.sh (removed), agent-kill.sh (removed), agent-send.sh (removed), agent-audit.sh (removed)

6. **`skills/cmux-agent-workflows/scripts/poll-wait.sh`** — Rewrite to remove opencode/codex plugin path comments; the dual-source event+poll mechanism stays but Pi-specific completion signals replace CTB-DONE / lifecycle idle.

### Phase 3 — Skills (documentation)

7. **`skills/cmux-agent-workflows/SKILL.md`** — Entire skill: remove (replaced by Pi-native workflows)
8. **`skills/cmux-agent-workflows-lite/SKILL.md`** — Remove worker references (agent-kill.sh example, codex gotchas link)
9. **`skills/cmux-agent-workflows/WAIT_WITHOUT_SLEEP.md`** — Entire file: remove (opencode/codex plugin infra docs)
10. **`skills/cmux-agent-workflows/templates/worker-prompt.md`** — Remove or rewrite `BACKEND: codex|opencode` field

### Phase 4 — Tests

11. **`tests/test_agent_spawn_race.sh`** — Remove entire file (codex mock + worker spawn tests)
12. **`tests/test_agent_readiness_probe.sh`** — Remove entire file (opencode/codex readiness patterns)
13. **`tests/fixtures/opencode-narrow-pane-footer.txt`** — Remove fixture
14. **`tests/test_agent_audit.sh`** — Remove entire file (worker audit tests)
15. **`tests/test_poll_wait.sh`** — Rewrite: remove opencode plugin path setup, keep event-driven waiter tests with Pi-specific events

### Phase 5 — bin/ scripts (MIGRATE)

16. **`bin/board-config`** — Update `auto_detect_provider()` and `DEFAULT_MODELS_JSON` for Pi provider IDs
17. **`bin/board-model`** — Update `VALID_PROVIDERS`, `auto_detect_provider()`, `DEFAULT_MODELS_JSON`, usage text

### Phase 6 — Skills model/config docs (MIGRATE)

18. **`skills/board-model/SKILL.md`** — Update provider enum docs and examples
19. **`skills/board-config/SKILL.md`** — Update `--provider` flag docs
20. **`docs/delegation-policy.md`** — Rewrite tier defaults and budget policy for Pi
21. **`docs/cmux-cheat-sheet.md`** — Update hook installation section
22. **`docs/agent-notifications.md`** — Remove codex/opencode notification sections

### Phase 7 — Research docs (MIGRATE)

23. **`docs/orchestrator-token-efficiency-research.md`** — Update to reflect removal of codex gotchas content
24. **`docs/ORCHESTRATOR.md`** — Remove the opencode/codex worker spawn step from the workflow
25. **`docs/research/cmux-notify-feed-orchestrator.md`** — Update to reflect Pi architecture
26. **`tests/test_opencode_bin_resolve.sh`** — Rewrite for Pi plugin resolution
27. **`tests/test_board_config.sh`** — Update model assertions
28. **`tests/test_board_model.sh`** — Update provider assertions

---

## 3. KEEP — do not touch (orchestrator host / provider IDs)

These references are about OpenCode/Codex as **orchestrator hosts** or as **provider ID strings** in config data. They are NOT worker launch/detect/ready/kill logic.

| File | Reason |
|------|--------|
| `.opencode/opencode.json` | Orchestrator host plugin manifest |
| `.opencode/plugins/cmux-board.mjs` | Orchestrator host plugin (board tools + session.idle hook) |
| `.opencode/package.json` | Host plugin SDK dependency |
| `.opencode/agent/orchestrator.md` | Host agent configuration (model, rules) — except L37 (worker dispatch ref) which is REMOVE |
| `skills/board-onboard-lite/SKILL.md:3` | Skill description mentioning "codex trust" as a topic the skill covers |
| `skills/board-onboard/SKILL.md:3` | Skill description mentioning "codex trust behavior" as a topic |
| `docs/orchestrator-diagnostics.md:4` | Lists Codex/OpenCode as possible orchestrator *host* agents |
| `docs/codex-port.md` (all lines except worker examples) | Describes Codex/OpenCode as orchestrator host platforms for the board plugin |

---

## 4. Tests: delete vs. rewrite

| Test file | Action | Rationale |
|-----------|--------|-----------|
| `test_agent_spawn_race.sh` | **Delete** | Tests worker spawn with codex mock — no replacement needed |
| `test_agent_readiness_probe.sh` | **Delete** | Tests worker readiness patterns — no replacement needed |
| `fixtures/opencode-narrow-pane-footer.txt` | **Delete** | Opencode-specific fixture |
| `test_agent_audit.sh` | **Delete** | Tests worker audit/process-scanning logic |
| `test_opencode_bin_resolve.sh` | **Rewrite** | Tests plugin bin resolution; concept stays under Pi but paths change |
| `test_poll_wait.sh` | **Rewrite** | Event-driven waiter concept stays; remove opencode plugin setup, adapt for Pi events |
| `test_board_config.sh` | **Rewrite** | Model assertions update for Pi provider IDs |
| `test_board_model.sh` | **Rewrite** | Provider assertions update for Pi provider IDs |

---

## 5. Dependency map

```
lib.sh
  ├── agent-spawn.sh    → REMOVE (phase 1)
  ├── agent-kill.sh     → REMOVE (phase 1)
  ├── agent-send.sh     → REMOVE (phase 1)
  ├── agent-audit.sh    → REMOVE (phase 1)
  ├── poll-wait.sh      → MIGRATE (phase 2)
  └── poll-push.sh      → no changes needed (no opencode/codex refs)

bin/board-config        → MIGRATE (phase 5)
bin/board-model         → MIGRATE (phase 5)

.opencode/              → KEEP (orchestrator host)
  ├── opencode.json
  ├── plugins/cmux-board.mjs
  └── package.json

Skills (REMOVE):
  cmux-agent-workflows/SKILL.md
  cmux-agent-workflows-lite/SKILL.md
  cmux-agent-workflows/WAIT_WITHOUT_SLEEP.md
  cmux-agent-workflows/templates/worker-prompt.md

Skills (MIGRATE):
  board-model/SKILL.md
  board-config/SKILL.md

Skills (KEEP):
  board-onboard-lite/SKILL.md
  board-onboard/SKILL.md

Tests (DELETE):
  test_agent_spawn_race.sh
  test_agent_readiness_probe.sh + fixture
  test_agent_audit.sh

Tests (REWRITE):
  test_opencode_bin_resolve.sh
  test_poll_wait.sh
  test_board_config.sh
  test_board_model.sh
```

---

*Generated 2026-06-12 — research for #98.*
