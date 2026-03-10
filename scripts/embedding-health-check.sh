#!/usr/bin/env bash
# embedding-health-check.sh — Check if OpenAI embedding API is available
# Intent: Resilient [I08], Observable [I17].
# If API is back online, auto-flush the chart queue.
# Alerts after 3 consecutive failures (1.5 hours).
set -eo pipefail

LOG="/root/.openclaw/logs/embedding-health.log"
STATE_FILE="/root/.openclaw/embedding-health-state.json"
ALERT_THRESHOLD=3
mkdir -p "$(dirname "$LOG")"

# Read consecutive failure count
FAILURES=0
if [ -f "$STATE_FILE" ]; then
  FAILURES=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('consecutive_failures',0))" 2>/dev/null || echo 0)
fi

STATUS=$(docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway node -e "
const fetch = globalThis.fetch;
(async () => {
  try {
    const r = await fetch('https://api.openai.com/v1/embeddings', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + process.env.OPENAI_API_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'text-embedding-3-small', input: 'health check' })
    });
    console.log(r.status);
  } catch(e) { console.log('error'); }
})();
" 2>/dev/null || echo "unreachable")

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$STATUS" = "200" ]; then
  echo "[$TS] EMBEDDING API: OK" >> "$LOG"
  # Recovery alert if was previously failing
  if [ "$FAILURES" -ge "$ALERT_THRESHOLD" ]; then
    echo "[$TS] RECOVERED after $FAILURES consecutive failures" >> "$LOG"
    docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway \
      openclaw message send --channel discord --account robert --target ops-alerts \
      -m "Embedding API RECOVERED after ${FAILURES} failures ($(( FAILURES * 30 )) min downtime)" 2>/dev/null | grep -v "level=warning" || true
  fi
  # Reset failure count (atomic write via temp file)
  echo '{"consecutive_failures":0,"last_status":"ok","last_check":"'"$TS"'"}' > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
  # Auto-flush chart queue if there are pending entries
  if [ -f /root/.openclaw/chart-queue.jsonl ]; then
    PENDING=$(grep -c '"pending"' /root/.openclaw/chart-queue.jsonl 2>/dev/null || echo 0)
    if [ "$PENDING" -gt 0 ]; then
      echo "[$TS] AUTO-FLUSH: $PENDING pending charts" >> "$LOG"
      chart-queue flush >> "$LOG" 2>&1
    fi
  fi
else
  FAILURES=$((FAILURES + 1))
  echo "[$TS] EMBEDDING API: $STATUS (unavailable) — failure #${FAILURES}" >> "$LOG"
  echo '{"consecutive_failures":'"$FAILURES"',"last_status":"'"$STATUS"'","last_check":"'"$TS"'"}' > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
  issue-log "Embedding API unavailable (status: $STATUS). Ollama may be down." --source embedding-health-check --severity high 2>/dev/null || true
  # Alert after threshold consecutive failures
  if [ "$FAILURES" -eq "$ALERT_THRESHOLD" ]; then
    echo "[$TS] ALERT: ${FAILURES} consecutive failures — notifying" >> "$LOG"
    docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway \
      openclaw message send --channel discord --account robert --target ops-alerts \
      -m "ALERT: Embedding API down for ${FAILURES} consecutive checks ($(( FAILURES * 30 )) min). Status: ${STATUS}" 2>/dev/null | grep -v "level=warning" || true
    /root/.openclaw/scripts/ops-db.py incident open "Embedding API extended outage" \
      --severity high --desc "${FAILURES} consecutive failures over $(( FAILURES * 30 )) minutes" 2>/dev/null || true
  fi
fi
