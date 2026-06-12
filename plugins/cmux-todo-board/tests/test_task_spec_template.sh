#!/bin/bash
# Test: task-spec.template.md exists and covers all 13 required sections
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$HERE/.." && pwd)"
REPO_DIR="$(cd "$PLUGIN_DIR/../.." && pwd)"

TEMPLATE="$PLUGIN_DIR/skills/cmux-agent-workflows/templates/task-spec.template.md"
GUIDE="$REPO_DIR/docs/task-spec-template.md"

pass=0
fail=0

pass_msg()  { echo "PASS: $1"; }
fail_msg() { echo "FAIL: $1"; fail=$((fail + 1)); }

# --------------------------------------------------------------------------
# 1. Template file exists and is non-empty
# --------------------------------------------------------------------------
if [ -f "$TEMPLATE" ] && [ -s "$TEMPLATE" ]; then
  pass_msg "template file exists and non-empty"
  pass=$((pass + 1))
else
  fail_msg "template file missing or empty: $TEMPLATE"
fi

# --------------------------------------------------------------------------
# 2. Template contains every required section heading
# --------------------------------------------------------------------------
required_sections="
# Task:
## Goal
## Source
## Files (create/edit ONLY these)
## CONTENTION GUARD
## Behavior / Contract
## Test
## Acceptance
## Verify (before pushing)
## Commit / push
## CHANGELOG
## Bounds
## Completion
"

missing=0
while IFS= read -r heading; do
  [ -z "$heading" ] && continue
  # Escape regex metacharacters so '#' '#' '/' are literal
  pattern="$(printf '%s' "$heading" | sed 's/[^^]/[&]/g; s/\^/\\^/g')"
  if grep -qF "$heading" "$TEMPLATE"; then
    pass_msg "template contains heading: $heading"
    pass=$((pass + 1))
  else
    fail_msg "template missing heading: $heading"
    missing=$((missing + 1))
  fi
done <<< "$required_sections"

if [ "$missing" -gt 0 ]; then
  fail_msg "$missing required heading(s) missing from template"
  fail=$((fail + missing))
fi

# --------------------------------------------------------------------------
# 3. Template documents the CONTENTION GUARD marker pattern (# ---)
# --------------------------------------------------------------------------
if grep -q '# ---' "$TEMPLATE"; then
  pass_msg "template documents CONTENTION GUARD marker pattern (# ---)"
  pass=$((pass + 1))
else
  fail_msg "template does NOT document CONTENTION GUARD marker (# ---)"
  fail=$((fail + 1))
fi

# --------------------------------------------------------------------------
# 4. Guide doc exists and references the template path
# --------------------------------------------------------------------------
if [ -f "$GUIDE" ] && [ -s "$GUIDE" ]; then
  pass_msg "guide doc exists and non-empty: docs/task-spec-template.md"
  pass=$((pass + 1))
else
  fail_msg "guide doc missing or empty: $GUIDE"
  fail=$((fail + 1))
fi

if grep -q 'task-spec\.template\.md' "$GUIDE"; then
  pass_msg "guide doc references the template path"
  pass=$((pass + 1))
else
  fail_msg "guide doc does NOT reference template path"
  fail=$((fail + 1))
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo "---"
echo "Results: $pass PASS, $fail FAIL"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
