# Delegation Model Policy

> Models come from the profile table in `bin/board-config`
> (`--get-profile <name> --json`). Paid profiles (`frontend`, `frontend-top`)
> are gated behind explicit user permission.

## Model Profiles

Each profile loads its prompt asset from `prompts/pi/roles/<role>.md`; multiple
profiles may reuse one role.

| Profile | Provider / Model | Thinking | Role asset | Use |
|---|---|---|---|---|
| backend | `opencode-go/deepseek-v4-pro` | high | backend | Complex / reasoning-heavy: main IMPLEMENT. |
| backend-fast | `opencode/deepseek-v4-flash-free` | low | backend | Mechanics, glue, routine. Default free worker. |
| repo-scout | `opencode/nemotron-3-ultra-free` | medium | review | Read-only repo reconnaissance (no write tools). |
| docs | `opencode/mimo-v2.5-free` | low | docs | Documentation. Free worker. |
| test | `openai-codex/gpt-5.4-mini` | medium | backend | Test authoring/execution. |
| tiny-patch | `openai-codex/gpt-5.4-mini` | low | backend | Small targeted patches. |
| review | `opencode-go/deepseek-v4-pro` | high | review | REVIEW of heavy PRs (read-only). |
| frontend | `anthropic/claude-sonnet-4-6` | medium | frontend | UI work. **Gated: user-permission** (paid). |
| frontend-top | `anthropic/claude-opus-4-8` | high | frontend-top | Hard UI work. **Gated: user-permission** (paid). |

## Rules

- **Docs → docs profile ONLY** (never backend/review).
- UI/widget DESIGN (sparkline, layout, colors) → the Opus orchestrator codes it itself (not delegated); widget logic/config is still delegated.
- Finance-critical pipeline: backend IMPLEMENT → review REVIEW.
- Hard gate is ALWAYS the orchestrator's: independently verify agent output (typecheck + tests + live DB/KV) before merge; never trust self-report.
- ≤2 agents in flight at once.

## Avoid / Unverified

- `opencode/nemotron-3-ultra-free` — liveness ok but breaks on real agentic coding (malformed tool-call JSON); not for tool-heavy work.
- `nvidia/qwen/qwen3-coder-480b-a35b-instruct` — strong coding candidate but liveness was empty (likely needs API key in opencode auth); check key first.
