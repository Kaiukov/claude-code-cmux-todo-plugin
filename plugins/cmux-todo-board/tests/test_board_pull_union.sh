#!/usr/bin/env bash
set -euo pipefail

# test_board_pull_union.sh — pure-bash test for the union_issues function
# Does NOT hit the network.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Define union_issues identically to bin/board-pull for testability
# (the function is intentionally a standalone pure-bash+jq unit)
union_issues() {
  if [[ $# -eq 0 ]]; then
    printf '[]\n'
    return
  fi
  printf '%s\n' "$@" | jq -s '
    add
    | unique_by(.number)
    | sort_by(.number)
  '
}

# Helper: normalize both expected and actual via jq -c for comparison
assert_json_eq() {
  local test_name="$1" actual="$2" expected="$3"
  local actual_norm expected_norm
  actual_norm=$(echo "$actual" | jq -c '.')
  expected_norm=$(echo "$expected" | jq -c '.')
  if [[ "$actual_norm" == "$expected_norm" ]]; then
    echo "PASS"
  else
    echo "FAIL: got $actual_norm"
    echo "      expected $expected_norm"
    exit 1
  fi
}

echo "--- Test 1: union of two disjoint arrays ---"
a='[{"number":1,"title":"A"},{"number":3,"title":"C"}]'
b='[{"number":2,"title":"B"},{"number":4,"title":"D"}]'
result=$(union_issues "$a" "$b")
expected='[{"number":1,"title":"A"},{"number":2,"title":"B"},{"number":3,"title":"C"},{"number":4,"title":"D"}]'
assert_json_eq "Test 1" "$result" "$expected"

echo "--- Test 2: union with overlapping issues (dedup by .number) ---"
a='[{"number":1,"title":"A_v1"},{"number":2,"title":"B"}]'
b='[{"number":1,"title":"A_v2"},{"number":3,"title":"C"}]'
result=$(union_issues "$a" "$b")
# unique_by keeps the first occurrence, so A_v1 wins for number 1
expected='[{"number":1,"title":"A_v1"},{"number":2,"title":"B"},{"number":3,"title":"C"}]'
assert_json_eq "Test 2" "$result" "$expected"

echo "--- Test 3: single array passed through ---"
a='[{"number":5,"title":"E"},{"number":3,"title":"C"},{"number":1,"title":"A"}]'
result=$(union_issues "$a")
expected='[{"number":1,"title":"A"},{"number":3,"title":"C"},{"number":5,"title":"E"}]'
assert_json_eq "Test 3" "$result" "$expected"

echo "--- Test 4: no arrays returns empty JSON array ---"
result=$(union_issues)
expected='[]'
assert_json_eq "Test 4" "$result" "$expected"

echo "--- Test 5: empty array in union is ignored ---"
a='[{"number":1,"title":"A"}]'
b='[]'
result=$(union_issues "$a" "$b")
expected='[{"number":1,"title":"A"}]'
assert_json_eq "Test 5" "$result" "$expected"

echo "--- Test 6: three arrays, overlaps across all ---"
a='[{"number":1,"title":"A"},{"number":2,"title":"B"}]'
b='[{"number":2,"title":"B2"},{"number":3,"title":"C"}]'
c='[{"number":3,"title":"C2"},{"number":4,"title":"D"}]'
result=$(union_issues "$a" "$b" "$c")
expected='[{"number":1,"title":"A"},{"number":2,"title":"B"},{"number":3,"title":"C"},{"number":4,"title":"D"}]'
assert_json_eq "Test 6" "$result" "$expected"

echo ""
echo "All union_issues tests passed."

# --- filter_by_labels tests ---

filter_by_labels() {
  local labels_csv="$1" issues_json="$2"

  if [[ -z "$labels_csv" ]]; then
    printf '%s\n' "$issues_json"
    return
  fi

  local labels_json
  labels_json=$(echo "$labels_csv" | tr ',' '\n' | tr -d ' ' | jq -R -s 'split("\n") | map(select(length > 0))')

  echo "$issues_json" | jq --argjson labels "$labels_json" '
    map(select([.labels[].name] as $issue_labels | any($labels[]; . as $lbl | $issue_labels | index($lbl))))
  '
}

echo "--- Test 7: filter_by_labels keeps issues whose labels intersect ---"
issues='[{"number":1,"labels":[{"name":"ready"}]},{"number":2,"labels":[{"name":"done"}]},{"number":3,"labels":[]}]'
result=$(filter_by_labels "ready,inbox" "$issues")
expected='[{"number":1,"labels":[{"name":"ready"}]}]'
assert_json_eq "Test 7" "$result" "$expected"

echo "--- Test 8: filter_by_labels drops issues with no matching label ---"
issues='[{"number":1,"labels":[{"name":"ready"}]},{"number":2,"labels":[{"name":"done"}]}]'
result=$(filter_by_labels "inbox" "$issues")
expected='[]'
assert_json_eq "Test 8" "$result" "$expected"

echo "--- Test 9: filter_by_labels empty csv keeps all ---"
issues='[{"number":1,"labels":[{"name":"ready"}]},{"number":2,"labels":[{"name":"done"}]}]'
result=$(filter_by_labels "" "$issues")
expected='[{"number":1,"labels":[{"name":"ready"}]},{"number":2,"labels":[{"name":"done"}]}]'
assert_json_eq "Test 9" "$result" "$expected"

echo "--- Test 10: filter_by_labels issue with no labels dropped when csv non-empty ---"
issues='[{"number":1,"labels":[{"name":"ready"}]},{"number":2,"labels":[]},{"number":3,"labels":[{"name":"inbox"}]}]'
result=$(filter_by_labels "ready" "$issues")
expected='[{"number":1,"labels":[{"name":"ready"}]}]'
assert_json_eq "Test 10" "$result" "$expected"

echo ""
echo "All filter_by_labels tests passed."
