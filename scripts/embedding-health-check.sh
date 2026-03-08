#!/usr/bin/env bash
# embedding-health-check.sh — Check if OpenAI embedding API is available
# Intent: Resilient [I08], Observable [I17].
# If API is back online, auto-flush the chart queue.
set -eo pipefail

LOG="/root/.openclaw/logs/embedding-health.log"
mkdir -p "$(dirname "$LOG")"

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
  # Auto-flush chart queue if there are pending entries
  if [ -f /root/.openclaw/chart-queue.jsonl ]; then
    PENDING=$(grep -c '"pending"' /root/.openclaw/chart-queue.jsonl 2>/dev/null || echo 0)
    if [ "$PENDING" -gt 0 ]; then
      echo "[$TS] AUTO-FLUSH: $PENDING pending charts" >> "$LOG"
      chart-queue flush >> "$LOG" 2>&1
    fi
  fi
else
  echo "[$TS] EMBEDDING API: $STATUS (unavailable)" >> "$LOG"
  issue-log "Embedding API unavailable (status: $STATUS). Ollama may be down." --source embedding-health-check --severity high 2>/dev/null || true
fi
