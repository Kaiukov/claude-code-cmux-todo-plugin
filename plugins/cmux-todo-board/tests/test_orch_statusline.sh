#!/usr/bin/env bash
# Tests orch-statusline run-record resolution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUSLINE_BIN="$PLUGIN_ROOT/bin/orch-statusline"

if [[ ! -f "$STATUSLINE_BIN" ]]; then
  echo "FAIL: orch-statusline not found at $STATUSLINE_BIN"
  exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat > "$TMPDIR/bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  list-sessions)
    if [[ -n "${TMUX_SESSIONS:-}" ]]; then
      printf '%s\n' "$TMUX_SESSIONS"
    fi
    ;;
  *)
    echo "unsupported tmux mock call: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$TMPDIR/bin/tmux"

cat > "$TMPDIR/bin/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${PS_LINES:-}" ]]; then
  printf '%s\n' "$PS_LINES"
fi
EOF
chmod +x "$TMPDIR/bin/ps"

run_statusline() {
  local cwd="$1" plugin_root="$2" repo_root="${3:-}" tmux_sessions="${4:-}" ps_lines="${5:-}"
  (
    cd "$cwd"
    export PATH="$TMPDIR/bin:$PATH"
    export CLAUDE_PLUGIN_ROOT="$plugin_root"
    if [[ -n "$repo_root" ]]; then
      export ORCH_REPO_ROOT="$repo_root"
    else
      unset ORCH_REPO_ROOT
    fi
    export TMUX_SESSIONS="$tmux_sessions"
    export PS_LINES="$ps_lines"
    printf '{"cwd":"%s"}\n' "$PWD" | "$STATUSLINE_BIN"
  )
}

failures=0

# -------------------------------------------------------------------
# Test 1: ORCH_REPO_ROOT wins over plugin-root and cwd records.
# -------------------------------------------------------------------
HOST_ROOT="$TMPDIR/host-repo"
PLUGIN_A="$TMPDIR/plugin-a"
CWD_A="$TMPDIR/cwd-a"
mkdir -p "$HOST_ROOT/.tasks/orchestrator/runs" "$PLUGIN_A" "$CWD_A/.tasks/orchestrator/runs"

cat > "$HOST_ROOT/.tasks/orchestrator/runs/157-docs-20260614T143738Z.json" <<'EOF'
{
  "model": "openai-codex/gpt-5.4-mini",
  "status": "running"
}
EOF
cat > "$CWD_A/.tasks/orchestrator/runs/157-docs-20260614T143739Z.json" <<'EOF'
{
  "model": "wrong-model",
  "status": "running"
}
EOF

output="$(run_statusline "$CWD_A" "$PLUGIN_A" "$HOST_ROOT" "orch-157-docs")"
if [[ "$output" == "🤖 orch-157-docs · openai-codex/gpt-5.4-mini [running]" ]]; then
  echo "PASS: host-repo record wins"
else
  echo "FAIL: $output"
  failures=$((failures + 1))
fi

# -------------------------------------------------------------------
# Test 2: host==plugin still resolves with the existing layout.
# -------------------------------------------------------------------
SHARED_ROOT="$TMPDIR/shared-root"
CWD_B="$TMPDIR/cwd-b"
mkdir -p "$SHARED_ROOT/.tasks/orchestrator/runs" "$CWD_B"
cat > "$SHARED_ROOT/.tasks/orchestrator/runs/157-docs-20260614T152127Z.json" <<'EOF'
{
  "model": "openai-codex/gpt-5.4-mini",
  "status": "running"
}
EOF

output="$(run_statusline "$CWD_B" "$SHARED_ROOT" "$SHARED_ROOT" "orch-157-docs")"
if [[ "$output" == "🤖 orch-157-docs · openai-codex/gpt-5.4-mini [running]" ]]; then
  echo "PASS: shared host/plugin layout resolves"
else
  echo "FAIL: $output"
  failures=$((failures + 1))
fi

# -------------------------------------------------------------------
# Test 3: legacy cwd walk-up still works when no host root is provided.
# -------------------------------------------------------------------
LEGACY_CWD="$TMPDIR/legacy-workspace"
mkdir -p "$LEGACY_CWD/.tasks/orchestrator/runs"
cat > "$LEGACY_CWD/.tasks/orchestrator/runs/157-backend-20260614T152128Z.json" <<'EOF'
{
  "model": "openai-codex/gpt-5.4-mini",
  "status": "running"
}
EOF

output="$(run_statusline "$LEGACY_CWD" "$TMPDIR/empty-plugin-root" "" "orch-157-backend")"
if [[ "$output" == "🤖 orch-157-backend · openai-codex/gpt-5.4-mini [running]" ]]; then
  echo "PASS: legacy walk-up resolves"
else
  echo "FAIL: $output"
  failures=$((failures + 1))
fi

# -------------------------------------------------------------------
# Test 4: live runner fallback still fills the model when no record exists.
# -------------------------------------------------------------------
LIVE_CWD="$TMPDIR/live-workspace"
mkdir -p "$LIVE_CWD"
runner_line="root       4242  0.0  orch-tmux-runner.sh --run-file /tmp/157-backend-20260614T160000Z.json --model openai-codex/gpt-5.4-mini"
output="$(run_statusline "$LIVE_CWD" "$TMPDIR/empty-plugin-root-2" "$TMPDIR/empty-host-root" "orch-157-backend" "$runner_line")"
if [[ "$output" == "🤖 orch-157-backend · openai-codex/gpt-5.4-mini [running]" ]]; then
  echo "PASS: ps fallback resolves model"
else
  echo "FAIL: $output"
  failures=$((failures + 1))
fi

# -------------------------------------------------------------------
# Test 5: completed runs are reported once after tmux sessions disappear.
# -------------------------------------------------------------------
QUIET_ROOT="$TMPDIR/quiet-plugin-root"
QUIET_WORKSPACE="$TMPDIR/quiet-workspace"
mkdir -p "$QUIET_ROOT/.tasks/orchestrator/runs" "$QUIET_WORKSPACE"
cat > "$QUIET_ROOT/.tasks/orchestrator/runs/153-watch-20260614T160000Z.json" <<'EOF'
{
  "agent": "orch-153-watch",
  "model": "openai-codex/gpt-5.4-mini",
  "task": "watch finished",
  "status": "done"
}
EOF

output="$(run_statusline "$QUIET_WORKSPACE" "$QUIET_ROOT")"
if [[ "$output" == "✅ orch-153-watch · openai-codex/gpt-5.4-mini · watch finished [done]" ]]; then
  echo "PASS: completed run reported once"
else
  echo "FAIL: $output"
  failures=$((failures + 1))
fi
reported_at="$(jq -r '.reported_at // empty' "$QUIET_ROOT/.tasks/orchestrator/runs/153-watch-20260614T160000Z.json")"
if [[ -n "$reported_at" ]]; then
  echo "PASS: reported_at acknowledged"
else
  echo "FAIL: reported_at missing"
  failures=$((failures + 1))
fi
output="$(run_statusline "$QUIET_WORKSPACE" "$QUIET_ROOT")"
if [[ "$output" == "🟢 orchestrator idle — no agents running" ]]; then
  echo "PASS: completed run no longer repeats"
else
  echo "FAIL: $output"
  failures=$((failures + 1))
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All orch statusline tests passed."
else
  echo "$failures test(s) failed."
  exit 1
fi
