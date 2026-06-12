#!/usr/bin/env bash
# guardrail-ext-no-external-imports.sh — hard-gate: pi extensions MUST NOT import
# modules unavailable at runtime (Node built-ins + pi SDK only).
#
# Lesson from #91: importing "yaml" crashed pi on startup because the module is
# not available in pi's runtime. This guardrail catches that class of error for
# ALL extensions by grepping imports/requires and rejecting anything outside the
# allowed set.
#
# macOS bash 3.2 compatible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
EXT_DIR="$GIT_ROOT/.pi/extensions"
FAILURES=0

pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*"; FAILURES=$((FAILURES + 1)); }

# ── Allowed import sources (pi SDK + Node.js built-in modules) ──────────
# These are available in pi's Node.js runtime without npm install.
ALLOWED_IMPORTS=(
  # pi SDK
  "@mariozechner/pi-coding-agent"
  "@earendil-works/pi-coding-agent"
  "@earendil-works/pi-ai"
  "typebox"
  # Node.js built-ins (canonical list for the Node version pi bundles)
  "fs"        "path"        "os"          "crypto"
  "http"      "https"       "http2"       "net"
  "dgram"     "dns"         "tls"         "readline"
  "stream"    "events"      "util"        "buffer"
  "url"       "querystring" "assert"      "tty"
  "child_process" "cluster" "process"     "timers"
  "zlib"      "v8"          "vm"          "worker_threads"
  "perf_hooks" "inspector"  "string_decoder"
  "module"    "constants"
)

echo "=== guardrail: no external imports in .pi/extensions/*.ts ==="

if [[ ! -d "$EXT_DIR" ]]; then
  echo "SKIP: no .pi/extensions directory"
  exit 0
fi

# Collect every extension file
shopt -s nullglob
ext_files=( "$EXT_DIR"/*.ts )
shopt -u nullglob

if [[ ${#ext_files[@]} -eq 0 ]]; then
  echo "SKIP: no .ts extension files found"
  exit 0
fi

# ── Build an allowed-pattern grep for import sources ───────────────────
# We match       from "X"  or  from 'X'  or  require("X")  or  require('X')
# then check X against the allowed set.
build_allowed_alt() {
  local alt=""
  for m in "${ALLOWED_IMPORTS[@]}"; do
    # Escape regex-meaningful chars in module name (., +, *, etc.)
    # Do NOT escape / — it is literal in ERE.
    local esc="${m//./\\.}"
    if [[ -z "$alt" ]]; then
      alt="$esc"
    else
      alt="$alt|$esc"
    fi
  done
  echo "$alt"
}

ALLOWED_ALT="$(build_allowed_alt)"

for ext_file in "${ext_files[@]}"; do
  local_name="${ext_file##*/}"
  echo "  checking: $local_name"

  # ── Hard-deny specific regression: yaml module ───────────────────────
  if grep -nE 'from "yaml"|require\("yaml"\)|from '"'"'yaml'"'"'|require\('"'"'yaml'"'"'\)' "$ext_file"; then
    fail "$local_name imports banned 'yaml' module — extension will crash pi"
  else
    pass "$local_name: no banned 'yaml' import"
  fi

  # ── Extract all import sources ──────────────────────────────────────
  # Extract module names from:  from "X"  /  from 'X'  /  require("X")  /  require('X')
  import_sources=$( \
    { \
      grep -oE 'from "[^"]+"' "$ext_file" 2>/dev/null || true; \
      grep -oE "from '[^']+'" "$ext_file" 2>/dev/null || true; \
      grep -oE 'require\("[^"]+"\)' "$ext_file" 2>/dev/null || true; \
      grep -oE "require\('[^']+'\)" "$ext_file" 2>/dev/null || true; \
    } | sed -e 's/from "//;s/"$//' -e "s/from '//;s/'$//" -e 's/require("//;s/")$//' -e "s/require('//;s/')$//" \
    | sort -u)

  # ── Check each import source against allowed list ───────────────────
  for src in $import_sources; do
    # Skip relative imports (start with ./ or ../)
    if [[ "$src" == ./* ]] || [[ "$src" == ../* ]]; then
      continue
    fi
    # Check against allowed alternation
    if echo "$src" | grep -qE "^($ALLOWED_ALT)$"; then
      : # allowed
    else
      fail "$local_name imports DISALLOWED module: \"$src\" (not in pi-SDK / Node built-ins)"
    fi
  done

done

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "guardrail PASSED: no external imports in extensions"
  exit 0
else
  echo "guardrail FAILED: $FAILURES violation(s) — fix before merging"
  exit 1
fi
