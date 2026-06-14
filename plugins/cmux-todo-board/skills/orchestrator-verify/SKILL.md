---
name: orchestrator-verify
description: Run the hard gate, review the diff, and report pass or fail.
---

# orchestrator-verify

Use `bin/orch-verify`.

- Review the diff and commits yourself.
- Run the repo verify recipe.
- Collect a short pass/fail report.
- Never trust worker self-report as final proof.

If verification fails, report the failure plainly and stop.
