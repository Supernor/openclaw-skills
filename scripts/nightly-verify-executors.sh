#!/usr/bin/env bash
# nightly-verify-executors.sh — Verify task-runner + host-ops-executor invariants
# Cron: suitable for nightly slot (e.g. 3:30 AM UTC)
# Intent: Recoverable [I09]. Created: 2026-03-28.
#
# Checks:
#   1. task-runner.py has _resolve_home and _resolve_compose path resolvers
#   2. task-runner.py has check_agent_session_lock branch
#   3. task-runner.py circuit breaker counts only task-runner-owned blocked rows
#   4. host-ops-executor.py fetches one pending host_op task with fairness ordering
#
# Exit 0 if all pass, exit 1 if any fail. Output: one line per check.
set -eo pipefail

SCRIPTS="/root/.openclaw/scripts"
TASK_RUNNER="${SCRIPTS}/task-runner.py"
HOST_OPS="${SCRIPTS}/host-ops-executor.py"
FAILURES=0

check() {
    local label="$1" file="$2" pattern="$3"
    if grep -qP "$pattern" "$file" 2>/dev/null; then
        echo "PASS  $label"
    else
        echo "FAIL  $label"
        FAILURES=$((FAILURES + 1))
    fi
}

# --- File existence ---
for f in "$TASK_RUNNER" "$HOST_OPS"; do
    if [ ! -f "$f" ]; then
        echo "FAIL  file missing: $f"
        FAILURES=$((FAILURES + 1))
    fi
done

if [ "$FAILURES" -gt 0 ]; then
    echo "--- ${FAILURES} check(s) failed ---"
    exit 1
fi

# --- task-runner.py checks ---
check "task-runner: _resolve_home path resolver"    "$TASK_RUNNER" 'def _resolve_home\('
check "task-runner: _resolve_compose path resolver"  "$TASK_RUNNER" 'def _resolve_compose\('
check "task-runner: session-lock branch"             "$TASK_RUNNER" 'check_agent_session_lock'
check "task-runner: circuit breaker scope"           "$TASK_RUNNER" "blocked_by='task-runner'"

# --- host-ops-executor.py checks ---
check "host-ops: pending host_op fairness query"    "$HOST_OPS"    "WHERE status='pending' AND meta IS NOT NULL"
check "host-ops: host_op JSON filter"               "$HOST_OPS"    "json_extract\\(meta, '\\$\\.host_op'\\) IS NOT NULL"
check "host-ops: urgency + FIFO ordering"           "$HOST_OPS"    "ORDER BY CASE urgency .* id ASC LIMIT 1"

# --- Summary ---
TOTAL=7
PASSED=$((TOTAL - FAILURES))
echo "--- ${PASSED}/${TOTAL} passed ---"
[ "$FAILURES" -eq 0 ] && exit 0 || exit 1
