#!/bin/bash
# Morning Briefing — proactive daily update to Robert via Telegram
# Cron: daily at 7am EST (12:00 UTC)
# Converted from agent-based to bash-template: 2026-03-10 (saves ~$0.18/mo)
# Sends directly via openclaw message send (no agent call, zero token cost)

set -euo pipefail

COMPOSE="docker compose -f /root/openclaw/docker-compose.yml"
LOG="/root/.openclaw/logs/morning-briefing.log"
exec >> "$LOG" 2>&1
echo "=== Morning Briefing $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# --- Gather data ---

# System health
HEALTH=$($COMPOSE exec -T openclaw-gateway openclaw health 2>/dev/null | grep -v "level=warning" | head -3)
TELEGRAM=$(echo "$HEALTH" | grep -oP 'Telegram: \K\S+' || echo "?")
DISCORD=$(echo "$HEALTH" | grep -oP 'Discord: \K\S+' || echo "?")

# Cron health
CRON_FAILS=$(cron-health 2>/dev/null | grep -c "FAIL\|ERROR" || echo "0")

# Recent errors
RECENT_ERRORS=$($COMPOSE logs --since=8h openclaw-gateway 2>&1 | grep -c "isError=true" || echo "0")

# Chart + helm stats
CHART_COUNT=$(chart count 2>/dev/null | grep -oP '\d+' || echo "?")
HELM_TOTAL=$(wc -l < /root/.openclaw/helm-usage.log 2>/dev/null || echo "0")

# Satisfaction
SAT=$(/root/.openclaw/scripts/satisfaction-summary.sh 2>/dev/null || echo "Satisfaction: unavailable")

# --- Build briefing ---

ATTENTION=""
if [ "$RECENT_ERRORS" -gt 0 ] 2>/dev/null; then
  ATTENTION="⚠️ ${RECENT_ERRORS} errors in the last 8h — check gateway logs."
fi
if [ "$CRON_FAILS" -gt 0 ] 2>/dev/null; then
  ATTENTION="${ATTENTION}
⚠️ ${CRON_FAILS} cron failures detected."
fi

if [ -z "$ATTENTION" ]; then
  LEAD="All quiet overnight. No errors, no cron failures."
else
  LEAD="Heads up:
${ATTENTION}"
fi

BRIEFING="☀️ Morning Briefing

${LEAD}

System: Telegram ${TELEGRAM} | Discord ${DISCORD}
Chartroom: ${CHART_COUNT} charts
Helm: ${HELM_TOTAL} total calls
${SAT}

Have a good one, Robert."

# --- Send via Telegram directly (no agent call) ---

TARGET=$(telegram-resolve robert 2>/dev/null || echo "8561305605")

$COMPOSE exec -T openclaw-gateway \
  openclaw message send \
  --channel telegram \
  --account robert \
  --target "$TARGET" \
  -m "$BRIEFING" 2>&1 | tail -3

echo "=== Done $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
