---
name: orchestrator-finish
description: Close the local run and remind the human merge gate rules.
---

# orchestrator-finish

Close out the local run with `bin/orch-finish`.

- Clean session and runtime state.
- Summarize the final outcome.
- Remind that merge confirmation is explicit.
- Do not auto-merge.
- Do not deploy in V1.

Finish locally, then hand back control.
