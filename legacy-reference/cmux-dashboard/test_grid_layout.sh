#!/usr/bin/env bash
# Tests for balanced grid layout helper grid_pick_split (#97).
# Mocks `cmux` with canned JSON fixtures and asserts selection rules:
#   - Orchestrator surface is NEVER returned as a target.
#   - 0 workers with only orchestrator → empty (legacy fallback).
#   - 0 workers with browser sibling → targets the browser pane.
#   - 1 worker → targets the worker, direction=down (odd).
#   - 2 workers → targets shallowest worker, direction=right (even).
#   - 3 workers → direction=down (odd).
#   - 4 workers → direction=right (even).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_FILE="$REPO_ROOT/skills/cmux-agent-workflows/scripts/lib.sh"

if [[ ! -f "$LIB_FILE" ]]; then
  echo "FAIL: lib.sh not found at $LIB_FILE"
  exit 1
fi

source "$LIB_FILE"

failures=0
TESTDIR="$(mktemp -d)"
cleanup() { rm -rf "$TESTDIR"; }
trap cleanup EXIT

# --- Mock cmux: returns JSON from $GRID_FIXTURE file ---
cat > "$TESTDIR/cmux" << 'SCRIPT_EOF'
#!/usr/bin/env bash
case "$1" in
  tree) cat "${GRID_FIXTURE:-/dev/null}" ;;
  *) exit 0 ;;
esac
SCRIPT_EOF
chmod +x "$TESTDIR/cmux"

export PATH="$TESTDIR:$PATH"
# Unset CMUX_WORKSPACE_ID so the helper uses caller's workspace from JSON.
unset CMUX_WORKSPACE_ID

# ── Helper: write a fixture JSON file and run grid_pick_split ──
run_grid() {
  local fixture_file="$1"
  export GRID_FIXTURE="$fixture_file"
  grid_pick_split 2>/dev/null || true
}

# ══════════════════════════════════════════════════════════════════════
# Fixture 1: Orchestrator-only (0 panes besides orchestrator).
# Expected: empty (no non-orchestrator leaf → legacy fallback).
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 1: orchestrator-only workspace → empty ==="
F1="$TESTDIR/f1.json"
cat > "$F1" << 'EOF'
{
  "caller": {"surface_ref": "surface:10", "workspace_ref": "workspace:1"},
  "windows": [{
    "active": true,
    "workspaces": [{
      "ref": "workspace:1",
      "panes": [{
        "ref": "pane:1",
        "selected_surface_ref": "surface:10",
        "surfaces": [{"ref": "surface:10", "type": "terminal", "pane_ref": "pane:1"}]
      }]
    }]
  }]
}
EOF
result="$(run_grid "$F1")"
if [[ -z "$result" ]]; then
  echo "PASS: returned empty (legacy fallback)"
else
  echo "FAIL: expected empty, got '$result'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Fixture 2: orchestrator + browser pane (0 workers, non-orch leaf exists).
# Expected: targets browser surface, direction=right.
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 2: orchestrator + browser → targets browser, right ==="
F2="$TESTDIR/f2.json"
cat > "$F2" << 'EOF'
{
  "caller": {"surface_ref": "surface:10", "workspace_ref": "workspace:1"},
  "windows": [{
    "active": true,
    "workspaces": [{
      "ref": "workspace:1",
      "panes": [
        {
          "ref": "pane:1",
          "selected_surface_ref": "surface:10",
          "surfaces": [{"ref": "surface:10", "type": "terminal", "pane_ref": "pane:1"}]
        },
        {
          "ref": "pane:2",
          "selected_surface_ref": "surface:20",
          "surfaces": [{"ref": "surface:20", "type": "browser", "pane_ref": "pane:2"}]
        }
      ]
    }]
  }]
}
EOF
result="$(run_grid "$F2")"
if [[ "$result" == "surface:20 right" ]]; then
  echo "PASS: $result"
else
  echo "FAIL: expected 'surface:20 right', got '$result'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Fixture 3: 1 worker pane.
# Expected: targets the worker, direction=down (odd count).
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 3: 1 worker → targets worker, down ==="
F3="$TESTDIR/f3.json"
cat > "$F3" << 'EOF'
{
  "caller": {"surface_ref": "surface:10", "workspace_ref": "workspace:1"},
  "windows": [{
    "active": true,
    "workspaces": [{
      "ref": "workspace:1",
      "panes": [
        {
          "ref": "pane:1",
          "selected_surface_ref": "surface:10",
          "surfaces": [{"ref": "surface:10", "type": "terminal", "pane_ref": "pane:1"}]
        },
        {
          "ref": "pane:2",
          "selected_surface_ref": "surface:20",
          "surfaces": [{"ref": "surface:20", "type": "terminal", "pane_ref": "pane:2"}]
        }
      ]
    }]
  }]
}
EOF
result="$(run_grid "$F3")"
if [[ "$result" == "surface:20 down" ]]; then
  echo "PASS: $result"
else
  echo "FAIL: expected 'surface:20 down', got '$result'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Fixture 4: 2 worker panes.
# Expected: shallowest worker (lowest surface number), direction=right (even).
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 4: 2 workers → lowest surface, right ==="
F4="$TESTDIR/f4.json"
cat > "$F4" << 'EOF'
{
  "caller": {"surface_ref": "surface:10", "workspace_ref": "workspace:1"},
  "windows": [{
    "active": true,
    "workspaces": [{
      "ref": "workspace:1",
      "panes": [
        {"ref": "pane:1", "selected_surface_ref": "surface:10", "surfaces": [{"ref": "surface:10", "type": "terminal", "pane_ref": "pane:1"}]},
        {"ref": "pane:2", "selected_surface_ref": "surface:20", "surfaces": [{"ref": "surface:20", "type": "terminal", "pane_ref": "pane:2"}]},
        {"ref": "pane:3", "selected_surface_ref": "surface:30", "surfaces": [{"ref": "surface:30", "type": "terminal", "pane_ref": "pane:3"}]}
      ]
    }]
  }]
}
EOF
result="$(run_grid "$F4")"
# Workers are surface:20 and surface:30. Lowest = surface:20; 2 workers → even → right.
if [[ "$result" == "surface:20 right" ]]; then
  echo "PASS: $result"
else
  echo "FAIL: expected 'surface:20 right', got '$result'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Fixture 5: Orchestrator surface is NEVER returned as target.
# Use the 2-worker fixture but verify the result does NOT contain the
# orchestrator surface.
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 5: orchestrator surface (surface:10) NEVER returned ==="
if [[ "$result" != *"surface:10"* ]]; then
  echo "PASS: orchestrator surface excluded from target"
else
  echo "FAIL: orchestrator surface found in result '$result'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Fixture 6: 3 worker panes → direction=down (odd).
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 6: 3 workers → down ==="
F6="$TESTDIR/f6.json"
cat > "$F6" << 'EOF'
{
  "caller": {"surface_ref": "surface:10", "workspace_ref": "workspace:1"},
  "windows": [{
    "active": true,
    "workspaces": [{
      "ref": "workspace:1",
      "panes": [
        {"ref": "pane:1", "selected_surface_ref": "surface:10", "surfaces": [{"ref": "surface:10", "type": "terminal", "pane_ref": "pane:1"}]},
        {"ref": "pane:2", "selected_surface_ref": "surface:20", "surfaces": [{"ref": "surface:20", "type": "terminal", "pane_ref": "pane:2"}]},
        {"ref": "pane:3", "selected_surface_ref": "surface:30", "surfaces": [{"ref": "surface:30", "type": "terminal", "pane_ref": "pane:3"}]},
        {"ref": "pane:4", "selected_surface_ref": "surface:40", "surfaces": [{"ref": "surface:40", "type": "terminal", "pane_ref": "pane:4"}]}
      ]
    }]
  }]
}
EOF
result="$(run_grid "$F6")"
# 3 workers (odd) → down, lowest surface = surface:20
if [[ "$result" == "surface:20 down" ]]; then
  echo "PASS: $result"
else
  echo "FAIL: expected 'surface:20 down', got '$result'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Fixture 7: 4 worker panes → direction=right (even).
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 7: 4 workers → right ==="
F7="$TESTDIR/f7.json"
cat > "$F7" << 'EOF'
{
  "caller": {"surface_ref": "surface:10", "workspace_ref": "workspace:1"},
  "windows": [{
    "active": true,
    "workspaces": [{
      "ref": "workspace:1",
      "panes": [
        {"ref": "pane:1", "selected_surface_ref": "surface:10", "surfaces": [{"ref": "surface:10", "type": "terminal", "pane_ref": "pane:1"}]},
        {"ref": "pane:2", "selected_surface_ref": "surface:20", "surfaces": [{"ref": "surface:20", "type": "terminal", "pane_ref": "pane:2"}]},
        {"ref": "pane:3", "selected_surface_ref": "surface:30", "surfaces": [{"ref": "surface:30", "type": "terminal", "pane_ref": "pane:3"}]},
        {"ref": "pane:4", "selected_surface_ref": "surface:40", "surfaces": [{"ref": "surface:40", "type": "terminal", "pane_ref": "pane:4"}]},
        {"ref": "pane:5", "selected_surface_ref": "surface:50", "surfaces": [{"ref": "surface:50", "type": "terminal", "pane_ref": "pane:5"}]}
      ]
    }]
  }]
}
EOF
result="$(run_grid "$F7")"
# 4 workers (even) → right, lowest surface = surface:20
if [[ "$result" == "surface:20 right" ]]; then
  echo "PASS: $result"
else
  echo "FAIL: expected 'surface:20 right', got '$result'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Fixture 8: Workspace with tabbed panes (multiple surfaces per pane).
# Only the selected surface matters.
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 8: tabbed panes → only selected surface counted ==="
F8="$TESTDIR/f8.json"
cat > "$F8" << 'EOF'
{
  "caller": {"surface_ref": "surface:10", "workspace_ref": "workspace:1"},
  "windows": [{
    "active": true,
    "workspaces": [{
      "ref": "workspace:1",
      "panes": [
        {
          "ref": "pane:1",
          "selected_surface_ref": "surface:10",
          "surface_refs": ["surface:10"],
          "surfaces": [{"ref": "surface:10", "type": "terminal", "pane_ref": "pane:1", "selected": true, "selected_in_pane": true}]
        },
        {
          "ref": "pane:2",
          "selected_surface_ref": "surface:25",
          "surface_refs": ["surface:20", "surface:25"],
          "surfaces": [
            {"ref": "surface:20", "type": "terminal", "pane_ref": "pane:2", "selected": false, "selected_in_pane": false},
            {"ref": "surface:25", "type": "terminal", "pane_ref": "pane:2", "selected": true, "selected_in_pane": true}
          ]
        }
      ]
    }]
  }]
}
EOF
result="$(run_grid "$F8")"
# 1 worker (surface:25), odd → down
if [[ "$result" == "surface:25 down" ]]; then
  echo "PASS: $result (selected tab surface used)"
else
  echo "FAIL: expected 'surface:25 down', got '$result'"
  failures=$((failures + 1))
fi

# ══════════════════════════════════════════════════════════════════════
# Guard: agent-spawn.sh must never reassign DIR (script directory).
# The grid block MUST use a different variable (SPLIT_DIR) so the
# #91 and #118 paths ($DIR/.../extensions, $DIR/.../prompts) survive.
# ══════════════════════════════════════════════════════════════════════
echo "=== Test 9: agent-spawn.sh DIR never reassigned (guard #91/#118) ==="
SPAWN_SCRIPT="$REPO_ROOT/skills/cmux-agent-workflows/scripts/agent-spawn.sh"
# Count lines that assign DIR= (not SPLIT_DIR, HELPER_DIR, PROMPTS_DIR, etc.).
# The only legitimate DIR= is the script-directory assignment near the top.
dir_assignments="$(grep -cE '^[[:space:]]*DIR=' "$SPAWN_SCRIPT" 2>/dev/null || echo 0)"
if [[ "$dir_assignments" -eq 1 ]]; then
  echo "PASS: exactly 1 DIR= assignment in agent-spawn.sh"
else
  echo "FAIL: found $dir_assignments DIR= assignments (expected 1) — DIR may be clobbered"
  failures=$((failures + 1))
fi
# Confirm the one assignment is the script-directory one (line near top).
dir_line="$(grep -nE '^[[:space:]]*DIR=' "$SPAWN_SCRIPT" | head -1)"
if echo "$dir_line" | grep -q 'BASH_SOURCE'; then
  echo "PASS: sole DIR= references BASH_SOURCE (script dir)"
else
  echo "FAIL: sole DIR= line does not reference BASH_SOURCE: $dir_line"
  failures=$((failures + 1))
fi
# Assert the #91 and #118 blocks still reference $DIR for paths.
if grep -q '$DIR/../../../../../.pi/extensions/damage-control.ts' "$SPAWN_SCRIPT"; then
  echo "PASS: #91 damage-control path uses \$DIR"
else
  echo "FAIL: #91 damage-control path missing or altered"
  failures=$((failures + 1))
fi
if grep -q 'PROMPTS_DIR="$DIR/../../../prompts/pi"' "$SPAWN_SCRIPT"; then
  echo "PASS: #118 prompt assets path uses \$DIR"
else
  echo "FAIL: #118 prompt assets path missing or altered"
  failures=$((failures + 1))
fi

echo ""
if [[ $failures -eq 0 ]]; then
  echo "All grid layout tests passed."
else
  echo "$failures test(s) failed."
  exit 1
fi
