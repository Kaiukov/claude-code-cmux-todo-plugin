# Delegation Model Policy

> **Note:** codex / GPT weekly budget is PAUSED until **2026-06-11**. Until then,
> default to opencode deepseek. Before delegating, check the canonical
> `docs/models.json` for fresh model ids.

## Model Profiles

| Profile | Model | Role |
|------|-------|------|
| **backend-fast** | `opencode/deepseek-v4-flash-free` | Mechanics, docs, routine, glue/config/tests. Default free worker (replaces paid deepseek-v4-flash). |
| **backend** | `opencode-go/deepseek-v4-pro` | Complex / reasoning-heavy / finance-critical: main IMPLEMENT role. |
| **review** | `opencode-go/deepseek-v4-pro` | REVIEW of heavy/financial PRs after implementation. |
| **docs** | `opencode/mimo-v2.5-free` | Documentation tasks. Free worker. |
| **test** | `openai-codex/gpt-5.4-mini` | Test authoring and execution. |
| **tiny-patch** | `openai-codex/gpt-5.4-mini` | Small targeted patches. |

## Rules

- **Docs → docs profile ONLY** (never backend/review).
- UI/widget DESIGN (sparkline, layout, colors) → the Opus orchestrator codes it itself (not delegated); widget logic/config is still delegated.
- Finance-critical pipeline: backend IMPLEMENT → review REVIEW.
- Hard gate is ALWAYS the orchestrator's: independently verify agent output (typecheck + tests + live DB/KV) before merge; never trust self-report.
- ≤2 agents in flight at once.

## Avoid / Unverified

- `opencode/nemotron-3-ultra-free` — liveness ok but breaks on real agentic coding (malformed tool-call JSON); not for tool-heavy work.
- `nvidia/qwen/qwen3-coder-480b-a35b-instruct` — strong coding candidate but liveness was empty (likely needs API key in opencode auth); check key first.
