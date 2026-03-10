#!/bin/bash
# Morning Briefing — proactive daily update to Robert via Telegram
# Cron: daily at 7am EST (12:00 UTC)
# Uses oc-telegram for reliable delivery

set -euo pipefail

LOG="/root/.openclaw/logs/morning-briefing.log"
exec >> "$LOG" 2>&1
echo "=== Morning Briefing $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# Gather system health
HEALTH=$(docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw health 2>/dev/null | grep -v "level=warning" | head -10)

# Gather cron health
CRON_HEALTH=$(cron-health 2>/dev/null | tail -5 || echo "Cron health check unavailable")

# Gather recent errors from backbone
RECENT_ERRORS=$(docker compose -f /root/openclaw/docker-compose.yml logs --since=8h openclaw-gateway 2>&1 | grep -c "isError=true" || echo "0")

# Gather chart + helm stats
CHART_COUNT=$(chart count 2>/dev/null || echo "?")
HELM_TASKS=$(wc -l < /root/.openclaw/helm-usage.log 2>/dev/null || echo "0")

# Build the briefing prompt
BRIEFING="Generate a morning briefing for Robert. Raw system stats:

SYSTEM HEALTH:
$HEALTH

RECENT ERRORS (last 8h): $RECENT_ERRORS errors
CHARTROOM: $CHART_COUNT entries
HELM TASKS (total): $HELM_TASKS

Format as a warm, concise morning briefing from a trusted friend. Lead with anything that needs attention, then good news. Under 200 words. End with recommendation for today."

# Deliver via oc-telegram (reliable path)
oc-telegram relay "$BRIEFING" 2>&1 | tail -3

echo "=== Done $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
