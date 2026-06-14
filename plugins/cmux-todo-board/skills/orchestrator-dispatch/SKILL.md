---
name: orchestrator-dispatch
description: Dispatch one ready issue to the correct worker role.
---

# orchestrator-dispatch

Take one `ready` issue.

1. Choose the narrowest useful role: `repo-scout`, `backend`, or `reviewer`.
2. Dispatch it with `bin/orch-dispatch --task-id <issue> --role <role>`.
3. Keep the handoff compact and explicit.
4. Remember the worker runtime uses `openai-codex/gpt-5.4-mini` with thinking low|med|high; free models can 429 (issue #155).

Do not overfit the role choice.
