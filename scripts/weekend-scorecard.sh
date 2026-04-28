#!/usr/bin/env bash
# weekend-scorecard.sh — Measure reliability after unattended runs.
#
# WHEN TO USE: After any unattended period (weekend, overnight, multi-day).
# DON'T USE FOR: Real-time monitoring (use Truth Pass for that).
# IF SCORECARD SHOWS REGRESSION: Check blocked tasks first, then deferred failures.
#   DO THIS: sqlite3 /root/.openclaw/ops.db "SELECT id, agent, substr(outcome,1,80) FROM tasks WHERE status='blocked';"
#   VERIFY WITH: bash /root/.openclaw/scripts/verify-truth-pass.sh
#
# Usage:
#   weekend-scorecard.sh              # default: last 3 days
#   weekend-scorecard.sh --days 7     # custom window

set -uo pipefail

OPS_DB="/root/.openclaw/ops.db"
DAYS="${2:-3}"
if [ "${1:-}" = "--days" ] && [ -n "${2:-}" ]; then DAYS="$2"; fi

echo "============================================"
echo " Weekend Scorecard — last ${DAYS} days"
echo " Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"
echo ""

echo "--- Task Completion ---"
sqlite3 "$OPS_DB" "
SELECT
    date(updated_at) as day,
    SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as done,
    SUM(CASE WHEN status='blocked' THEN 1 ELSE 0 END) as blocked,
    SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END) as cancelled,
    COUNT(*) as total
FROM tasks
WHERE updated_at > datetime('now', '-${DAYS} days')
GROUP BY day ORDER BY day;
"
COMPLETED=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='completed' AND updated_at > datetime('now', '-${DAYS} days');")
BLOCKED=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='blocked' AND updated_at > datetime('now', '-${DAYS} days');")
TOTAL=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE updated_at > datetime('now', '-${DAYS} days');")
if [ "$TOTAL" -gt 0 ]; then
    RATE=$(echo "scale=0; $COMPLETED * 100 / $TOTAL" | bc)
    echo "Completion rate: ${COMPLETED}/${TOTAL} (${RATE}%)"
else
    echo "Completion rate: no tasks in window"
fi
echo ""

echo "--- Deferred Action Health ---"
sqlite3 "$OPS_DB" "SELECT status, COUNT(*) FROM deferred_actions GROUP BY status ORDER BY COUNT(*) DESC;"
STUCK=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM deferred_actions WHERE status='in_progress';")
DEAD=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM deferred_actions WHERE status='dead_letter';")
echo "Stuck in_progress: ${STUCK}"
echo "Dead letters: ${DEAD}"
echo ""

echo "--- Stale Claim Recoveries ---"
RECOVERED=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM intent_audit WHERE field_changed='stale_claim_recovered' AND changed_at > datetime('now', '-${DAYS} days');")
echo "Recovered in window: ${RECOVERED}"
echo ""

echo "--- Blocked Task Breakdown ---"
CURRENT_BLOCKED=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='blocked';")
echo "Currently blocked: ${CURRENT_BLOCKED}"
if [ "$CURRENT_BLOCKED" -gt 0 ]; then
    sqlite3 "$OPS_DB" "SELECT id, agent, substr(outcome, 1, 60) FROM tasks WHERE status='blocked' ORDER BY updated_at DESC LIMIT 5;"
fi
echo ""

echo "--- Unknown Host Ops ---"
UNKNOWN_OPS=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE outcome LIKE '%Unknown host operation%' AND updated_at > datetime('now', '-${DAYS} days');")
echo "Invalid host_ops in window: ${UNKNOWN_OPS}"
echo ""

echo "--- Auto-Correction Success ---"
CORRECTED_TOTAL=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE task LIKE 'Auto-corrected:%' AND updated_at > datetime('now', '-${DAYS} days');")
CORRECTED_OK=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE task LIKE 'Auto-corrected:%' AND status='completed' AND updated_at > datetime('now', '-${DAYS} days');")
echo "Auto-corrections: ${CORRECTED_OK}/${CORRECTED_TOTAL} completed"
echo ""

echo "--- Annotations ---"
MISSING=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM deferred_actions WHERE status IN ('failed','dead_letter') AND id NOT IN (SELECT action_id FROM deferred_action_annotations);")
SKILL_DEBT=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM kv WHERE key LIKE 'skill_debt:%';")
echo "Missing annotations: ${MISSING}"
echo "Skill debt entries: ${SKILL_DEBT}"
echo ""

echo "--- Services ---"
echo "Gateway: $(docker compose -f /root/openclaw/docker-compose.yml ps --format '{{.Status}}' 2>/dev/null | head -1)"
echo "Host-ops: $(systemctl is-active openclaw-host-ops 2>/dev/null)"
echo "Bridge: $(systemctl is-active openclaw-bridge-dev 2>/dev/null)"
echo "Auth watcher: $(systemctl is-active openclaw-codex-auth-watch 2>/dev/null)"
echo ""

echo "============================================"
echo " Verdict"
echo "============================================"
ISSUES=0
if [ "$CURRENT_BLOCKED" -gt 0 ]; then echo "  !! ${CURRENT_BLOCKED} blocked tasks need triage"; ISSUES=$((ISSUES+1)); fi
if [ "$STUCK" -gt 0 ]; then echo "  !! ${STUCK} deferred actions stuck in_progress"; ISSUES=$((ISSUES+1)); fi
if [ "$DEAD" -gt 0 ]; then echo "  !! ${DEAD} dead-letter actions (retries exhausted)"; ISSUES=$((ISSUES+1)); fi
if [ "$MISSING" -gt 0 ]; then echo "  !! ${MISSING} failures without annotations"; ISSUES=$((ISSUES+1)); fi
if [ "$UNKNOWN_OPS" -gt 0 ]; then echo "  !! ${UNKNOWN_OPS} invalid host_op tasks created"; ISSUES=$((ISSUES+1)); fi
if [ "$ISSUES" -eq 0 ]; then
    echo "  ALL CLEAR — system ran cleanly"
else
    echo "  ${ISSUES} issue(s) found — review above"
fi
