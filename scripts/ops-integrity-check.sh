#!/bin/bash
# ops-integrity-check — Validates data contracts in ops.db
# Fails closed: exits non-zero if any invariant broken
#
# Usage:
#   ops-integrity-check.sh          # Full check
#   ops-integrity-check.sh --quick  # Status/outcome only

set -euo pipefail

OPS_DB="/root/.openclaw/ops.db"
ERRORS=0

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "ops-integrity-check — Validates data contracts in ops.db"
    echo ""
    echo "Usage: ops-integrity-check.sh [--quick]"
    echo ""
    echo "  (no args)    Full check: status/outcome, JSON validity, blocked_by, engine_usage, WAL"
    echo "  --quick      Status/outcome and JSON validity only"
    echo ""
    echo "Exit codes:"
    echo "  0 = all checks passed"
    echo "  N = number of failures found"
    echo ""
    echo "Run this BEFORE and AFTER any data mutation to verify integrity."
    echo "If it exits non-zero, DO NOT proceed with further changes."
    echo ""
    echo "COMMON MISTAKES:"
    echo "  - Running --quick when you need full validation → use full check after schema changes"
    echo "  - Ignoring warnings → warnings become failures if left unfixed"
    exit 0
fi

check() {
    local name="$1" query="$2" expected="$3"
    result=$(sqlite3 "$OPS_DB" "$query" 2>&1)
    if [ "$result" = "$expected" ]; then
        echo "PASS: $name ($result)"
    else
        echo "FAIL: $name — expected '$expected', got '$result'"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== ops-integrity-check ==="
echo "Database: $OPS_DB"
echo "Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# 1. Status/outcome mismatch — completed tasks should not say BLOCKED
echo "--- Status/Outcome Consistency ---"
count=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='completed' AND (outcome LIKE 'BLOCKED%' OR outcome LIKE 'blocked%')")
if [ "$count" = "0" ]; then
    echo "PASS: No completed tasks with BLOCKED outcomes"
else
    echo "FAIL: $count completed tasks have BLOCKED outcomes"
    sqlite3 "$OPS_DB" "SELECT id, agent, substr(outcome,1,60) FROM tasks WHERE status='completed' AND (outcome LIKE 'BLOCKED%' OR outcome LIKE 'blocked%')"
    ERRORS=$((ERRORS + 1))
fi

# 2. Valid JSON in meta
echo ""
echo "--- Meta JSON Validity ---"
bad_json=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE meta IS NOT NULL AND TRIM(meta) <> '' AND json_valid(meta) = 0")
if [ "$bad_json" = "0" ]; then
    echo "PASS: All non-empty meta fields are valid JSON"
else
    echo "FAIL: $bad_json tasks have invalid JSON in meta"
    sqlite3 "$OPS_DB" "SELECT id, agent, substr(meta,1,80) FROM tasks WHERE meta IS NOT NULL AND TRIM(meta) <> '' AND json_valid(meta) = 0"
    ERRORS=$((ERRORS + 1))
fi

# 3. No orphaned blocked_by references
echo ""
echo "--- Blocked_by References ---"
orphans=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE blocked_by IS NOT NULL AND blocked_by != '' AND blocked_by != 'task-runner' AND CAST(blocked_by AS INTEGER) > 0 AND CAST(blocked_by AS INTEGER) NOT IN (SELECT id FROM tasks)")
if [ "$orphans" = "0" ]; then
    echo "PASS: No orphaned blocked_by references"
else
    echo "FAIL: $orphans tasks reference non-existent blocked_by IDs"
    ERRORS=$((ERRORS + 1))
fi

# 4. No in_progress tasks without started_at
echo ""
echo "--- In-Progress Consistency ---"
stuck=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='in_progress' AND started_at IS NULL")
if [ "$stuck" = "0" ]; then
    echo "PASS: All in_progress tasks have started_at"
else
    echo "WARN: $stuck in_progress tasks missing started_at"
fi

if [ "${1:-}" != "--quick" ]; then
    # 5. Engine usage sanity
    echo ""
    echo "--- Engine Usage Sanity ---"
    total_eu=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM engine_usage")
    echo "INFO: $total_eu engine_usage records"
    echo "INFO: Attempt/outcome split check:"
    sqlite3 "$OPS_DB" "SELECT engine, SUM(CASE WHEN success=1 THEN 1 ELSE 0 END) as ok, SUM(CASE WHEN success=0 THEN 1 ELSE 0 END) as fail, COUNT(*) as total FROM engine_usage GROUP BY engine ORDER BY total DESC"

    # 6. SQLite journal mode
    echo ""
    echo "--- SQLite Health ---"
    mode=$(sqlite3 "$OPS_DB" "PRAGMA journal_mode;")
    echo "INFO: Journal mode = $mode"
    if [ "$mode" = "wal" ]; then
        echo "PASS: WAL mode enabled"
    else
        echo "WARN: Not in WAL mode (currently: $mode)"
    fi
fi

echo ""
echo "=== Result: $ERRORS failures ==="
exit $ERRORS
