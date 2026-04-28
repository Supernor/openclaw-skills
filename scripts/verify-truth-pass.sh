#!/usr/bin/env bash
# verify-truth-pass.sh — Machine-checkable verification that Truth Pass metrics match reality.
#
# WHEN TO USE: After any schema migration, trigger change, or deferred-executor update.
# DON'T USE FOR: Routine health checks (use /api/truth-pass directly for that).
# IF ANY CHECK FAILS: The Truth Pass API is lying. Fix the query in dashboard-api.py.
# VERIFY: Compare the API count to the direct SQL count shown in the FAIL message.

set -euo pipefail

OPS_DB="/root/.openclaw/ops.db"
API="http://localhost:8083/api/truth-pass"
PASS=0
FAIL=0
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

check() {
    local name="$1"
    local sql_count="$2"
    local api_count="$3"
    if [ "$sql_count" = "$api_count" ]; then
        echo "  PASS: $name (SQL=$sql_count API=$api_count)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name (SQL=$sql_count API=$api_count) — MISMATCH"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Truth Pass Verification — $TS ==="

# Fetch API response once
API_JSON=$(curl -s "$API" 2>/dev/null)
if [ -z "$API_JSON" ]; then
    echo "FATAL: Cannot reach $API. Is Bridge running?"
    echo "DO THIS: systemctl restart openclaw-bridge-dev"
    exit 1
fi

api_val() { echo "$API_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',{}).get('count','?'))"; }

# Run checks
check "blocked_tasks" \
    "$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='blocked';")" \
    "$(api_val blocked_tasks)"

check "pending_deferred" \
    "$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM deferred_actions WHERE status='pending';")" \
    "$(api_val pending_deferred)"

check "failed_deferred_24h" \
    "$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM deferred_actions WHERE status='failed' AND executed_at > datetime('now', '-24 hours');")" \
    "$(api_val failed_deferred_24h)"

check "dead_letter" \
    "$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM deferred_actions WHERE status='dead_letter';")" \
    "$(api_val dead_letter)"

check "annotations_missing" \
    "$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM deferred_actions WHERE status IN ('failed','dead_letter') AND id NOT IN (SELECT action_id FROM deferred_action_annotations);")" \
    "$(api_val annotations_missing)"

check "triggers" \
    "$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger';")" \
    "$(api_val triggers)"

check "historical_explained" \
    "$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM deferred_action_annotations WHERE superseded_by IS NULL;")" \
    "$(api_val historical_explained)"

check "stale_claims_recovered_24h" \
    "$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM intent_audit WHERE field_changed='stale_claim_recovered' AND changed_at > datetime('now', '-24 hours');")" \
    "$(api_val stale_claims_recovered_24h)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "STATUS: FAIL — Truth Pass metrics do not match reality."
    echo "DO THIS: Check dashboard-api.py /api/truth-pass queries for bugs."
    exit 1
else
    echo "STATUS: PASS — All metrics match direct SQL."
    exit 0
fi
