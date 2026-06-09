#!/usr/bin/env bash
# Read an agent surface's visible screen. Thin wrapper for symmetry with the
# other agent-* helpers and a sane default line count.
#
# Usage: agent-screen.sh <surface> [lines]
#   agent-screen.sh surface:172 30
set -euo pipefail
[[ $# -ge 1 ]] || { echo "usage: agent-screen.sh <surface> [lines]" >&2; exit 1; }
exec cmux read-screen --surface "$1" --lines "${2:-25}"
