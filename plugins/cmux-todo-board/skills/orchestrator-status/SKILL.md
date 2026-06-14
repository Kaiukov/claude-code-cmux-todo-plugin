---
name: orchestrator-status
description: Show one compact V1 snapshot from the live orchestrator state.
---

# orchestrator-status

Show exactly one operational snapshot with `bin/orch-status`.

- Keep it compact.
- Include active runs, worker state, and next action if available.
- Do not read extra logs unless there is a specific reason.
- Treat the statusline as a turn-boundary snapshot, not a live monitor.

If the snapshot is unclear, refresh the status command once.
