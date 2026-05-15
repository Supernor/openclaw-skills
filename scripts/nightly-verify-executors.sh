#!/usr/bin/env bash
# nightly-verify-executors.sh — compatibility wrapper for executor invariants
#
# Keep this entrypoint for cron/manual callers, but delegate the actual checks to
# nightly-maint-check.py so there is only one canonical verifier to maintain.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
CHECKER="${SCRIPT_DIR}/nightly-maint-check.py"

if [ ! -f "$CHECKER" ]; then
    echo "FAIL: missing checker: $CHECKER" >&2
    exit 2
fi

exec "$PYTHON_BIN" "$CHECKER" "$@"
