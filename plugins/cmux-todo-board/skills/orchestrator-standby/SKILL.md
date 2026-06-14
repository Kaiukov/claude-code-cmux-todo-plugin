---
name: orchestrator-standby
description: Watch the run quietly and wake on real git or process signals.
---

# orchestrator-standby

Enter watcher mode after dispatch.

- Do not noisily poll the pane.
- Watch git, remote, and process signals with `bin/orch-watch`.
- Treat completion as git progress: a new commit or push, not a printed sentinel.
- Arm the background watcher so it wakes the orchestrator on commit or session death.
- Use pane output only as fallback.

Standby is passive until a meaningful change arrives.
