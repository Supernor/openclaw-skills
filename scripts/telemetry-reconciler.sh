#!/bin/bash
# telemetry-reconciler — Identifies engine_usage attempt/outcome mismatches
#
# Usage:
#   telemetry-reconciler.sh           # Dry-run analysis
#   telemetry-reconciler.sh --fix     # Apply fix (add is_failover tag to gemini-task)
#   telemetry-reconciler.sh --verify  # Verify fix was applied

set -euo pipefail

OPS_DB="/root/.openclaw/ops.db"

case "${1:-analyze}" in
    analyze|--dry-run)
        echo "=== Telemetry Reconciler — Dry Run ==="
        echo ""
        echo "--- engine_usage vs tasks comparison ---"
        echo ""
        echo "engine_usage says (attempt-level):"
        sqlite3 "$OPS_DB" "SELECT engine, SUM(CASE WHEN success=1 THEN 1 ELSE 0 END) as ok, SUM(CASE WHEN success=0 THEN 1 ELSE 0 END) as fail, COUNT(*) as total, ROUND(100.0*SUM(CASE WHEN success=1 THEN 1 ELSE 0 END)/COUNT(*),1) as pct FROM engine_usage GROUP BY engine ORDER BY total DESC"
        echo ""
        echo "tasks table says (outcome-level):"
        sqlite3 "$OPS_DB" "SELECT json_extract(meta,'$.host_op') as route, SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as ok, SUM(CASE WHEN status IN ('cancelled','blocked') THEN 1 ELSE 0 END) as fail, COUNT(*) as total, ROUND(100.0*SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END)/COUNT(*),1) as pct FROM tasks WHERE meta IS NOT NULL AND json_valid(meta) AND json_extract(meta,'$.host_op') IS NOT NULL GROUP BY json_extract(meta,'$.host_op') ORDER BY total DESC"
        echo ""
        echo "--- Mismatch Analysis ---"
        echo ""
        echo "Gemini: engine_usage logs free-tier ATTEMPTS as failures."
        echo "When paid failover succeeds, the task completes but engine_usage only shows the failure."
        sqlite3 "$OPS_DB" "SELECT 'gemini engine_usage: ' || COUNT(*) || ' failures' FROM engine_usage WHERE engine='gemini' AND success=0"
        sqlite3 "$OPS_DB" "SELECT 'gemini-run tasks: ' || SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) || '/' || COUNT(*) || ' completed (' || ROUND(100.0*SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END)/COUNT(*),1) || '%)' FROM tasks WHERE json_valid(COALESCE(meta,'{}')) AND json_extract(meta,'$.host_op')='gemini-run'"
        echo ""
        echo "FIX NEEDED: gemini-task should log paid failover success as a SECOND engine_usage entry."
        echo "Proposed: Add engine='gemini-paid', success=1 row when failover completes."
        ;;

    --fix)
        echo "=== Telemetry Fix ==="
        GEMINI_TASK="/root/.openclaw/scripts/gemini-task"
        if [ ! -f "$GEMINI_TASK" ]; then
            echo "Error: gemini-task not found at $GEMINI_TASK" >&2
            exit 1
        fi

        if grep -q "gemini-paid" "$GEMINI_TASK"; then
            echo "Fix already applied (gemini-paid logging exists)"
            exit 0
        fi

        echo "This fix should be applied manually by editing gemini-task."
        echo "Add this line BEFORE 'echo \"\$PAID_TEXT\"' in the paid failover success block:"
        echo ""
        echo '      sqlite3 /root/.openclaw/ops.db "INSERT INTO engine_usage (engine, success, prompt_len, duration_ms) VALUES ('\''gemini-paid'\'', 1, ${#ORIGINAL_PROMPT}, $((DURATION2 * 1000)));" 2>/dev/null || true'
        echo ""
        echo "This logs paid failover success separately from free-tier attempts."
        ;;

    --verify)
        echo "=== Telemetry Verification ==="
        if grep -q "gemini-paid" /root/.openclaw/scripts/gemini-task; then
            echo "PASS: gemini-task contains gemini-paid logging"
        else
            echo "FAIL: gemini-task missing gemini-paid logging"
            exit 1
        fi
        echo ""
        echo "Recent gemini-paid entries:"
        sqlite3 "$OPS_DB" "SELECT ts, engine, success, substr(meta,1,80) FROM engine_usage WHERE engine='gemini-paid' ORDER BY ts DESC LIMIT 5" 2>/dev/null || echo "(none yet — will appear after next gemini-task failover)"
        ;;

    *)
        echo "telemetry-reconciler — Analyze and fix engine_usage data"
        echo ""
        echo "  (no args)   Dry-run analysis"
        echo "  --fix       Apply gemini-paid logging fix"
        echo "  --verify    Verify fix was applied"
        ;;
esac
