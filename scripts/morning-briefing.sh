#!/bin/bash
# Alignment: Morning briefing — compact daily push to Robert via Telegram.
# Role: Pull digest from Bridge API, format as one short message with link.
# Dependencies: Bridge DEV API at localhost:8083, openclaw message send via Docker.
# Principle: Telegram points to Bridge. Don't duplicate content, just summarize + link.
# Cron: daily at 7am EST (12:00 UTC)
# Zero token cost — bash template, no agent call.

set -euo pipefail

COMPOSE="docker compose -f /root/openclaw/docker-compose.yml"
LOG="/root/.openclaw/logs/morning-briefing.log"
BRIDGE_URL="http://187.77.193.174:8083"
exec >> "$LOG" 2>&1
echo "=== Morning Briefing $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# --- Pull digest from Bridge API (source of truth) ---
DIGEST=$(curl -s http://localhost:8083/api/digest 2>/dev/null)

if [ -z "$DIGEST" ] || echo "$DIGEST" | grep -q '"error"'; then
  # Fallback if API is down
  BRIEFING="☀️ Morning — Bridge API is down. Check ${BRIDGE_URL}"
else
  # Parse digest fields
  TEXT=$(echo "$DIGEST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('text','No data'))" 2>/dev/null || echo "Digest unavailable")
  DECISIONS=$(echo "$DIGEST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('decisions_waiting',0))" 2>/dev/null || echo "0")
  TOTAL_IDEAS=$(echo "$DIGEST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total_ideas',0))" 2>/dev/null || echo "0")

  # Build compact message
  BRIEFING="☀️ ${TEXT}"

  # Add attention items
  if [ "$DECISIONS" -gt 0 ] 2>/dev/null; then
    BRIEFING="${BRIEFING}

🔔 ${DECISIONS} decisions waiting for you."
  fi

  # System health quick check
  RECENT_ERRORS=$(${COMPOSE} logs --since=8h openclaw-gateway 2>&1 | grep -c "isError=true" || echo "0")
  if [ "$RECENT_ERRORS" -gt 3 ] 2>/dev/null; then
    BRIEFING="${BRIEFING}

⚠️ ${RECENT_ERRORS} errors overnight — check Health tab."
  fi

  # Always end with Bridge link
  BRIEFING="${BRIEFING}

📋 Board: ${TOTAL_IDEAS} ideas → ${BRIDGE_URL}/#board
🔧 Workshop → ${BRIDGE_URL}/#workshop"
fi

# --- Send via Telegram (zero tokens) ---
TARGET=$(telegram-resolve robert 2>/dev/null || echo "8561305605")

$COMPOSE exec -T openclaw-gateway \
  openclaw message send \
  --channel telegram \
  --account robert \
  --target "$TARGET" \
  -m "$BRIEFING" 2>&1 | tail -3

echo "Sent: $BRIEFING"
echo "=== Done $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
