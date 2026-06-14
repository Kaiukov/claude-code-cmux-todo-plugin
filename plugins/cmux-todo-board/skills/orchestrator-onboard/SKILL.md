---
name: orchestrator-onboard
description: Primary V1 entrypoint — read status, explain rules, and hand off the next step.
---

# orchestrator-onboard

Start here.

1. Read the board status.
2. Show active runs with `bin/orch-status`.
3. State the V1 rules:
   - GitHub is the source of truth.
   - tmux is transport, not authority.
   - pi is the worker runtime.
   - workers commit locally and never push.
   - the orchestrator never merges without explicit user OK.
4. Pick the next step.
5. Hand off to `bin/orch-dispatch` if a ready issue exists.

Keep the summary short and action-first.
