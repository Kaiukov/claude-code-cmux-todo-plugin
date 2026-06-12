#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

need_cmd bash
need_cmd jq
need_cmd python3

echo "=== SHELL SYNTAX ==="
syntax_count=0
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  bash -n "$file"
  syntax_count=$((syntax_count + 1))
done < <(git ls-files '*.sh' | sort)
echo "PASS: bash -n on $syntax_count shell scripts"

echo "=== MANIFEST VALIDATION ==="
if command -v claude >/dev/null 2>&1; then
  echo "Using claude plugin validate ."
  claude plugin validate .
else
  echo "claude CLI not found; falling back to JSON manifest sanity"
  jq empty \
    .claude-plugin/marketplace.json \
    plugins/cmux-todo-board/.claude-plugin/plugin.json \
    plugins/cmux-todo-board/.codex-plugin/plugin.json \
    plugins/cmux-todo-board/.opencode/opencode.json
  echo "PASS: marketplace/plugin manifests are valid JSON"
fi

echo "=== HARD-GATE TESTS ==="
test_count=0
while IFS= read -r test_script; do
  [[ -n "$test_script" ]] || continue
  echo "--- $test_script ---"
  bash "$test_script"
  test_count=$((test_count + 1))
done < <(find plugins/cmux-todo-board/tests -maxdepth 1 -name 'test_*.sh' | sort)
echo "PASS: $test_count test scripts"

echo "=== HARD GATE: PASS ==="
