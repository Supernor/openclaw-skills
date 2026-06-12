#!/usr/bin/env bash
# embedding-health-check.sh — Probe the REAL memory/embedding chain.
# Intent: Resilient [I08], Observable [I17].
# Rewritten 2026-06-11: the old version probed api.openai.com with a dead
# zero-balance key and failed 4,314 consecutive times (~90 days of noise).
# What memory actually depends on now (fleet memory_search, chart queue):
#   1. Ollama embeddings reachable FROM INSIDE the gateway container
#      (agents.defaults.memorySearch -> http://host.docker.internal:11434/v1)
#   2. Vendored qmd binary present in container (memory.qmd.command)
#   3. memory-core plugin enabled in openclaw.json
# Alerts on state CHANGE (op-rule 6), threshold 3 consecutive failures.
# If chain is healthy, auto-flush pending chart queue.
set -eo pipefail

LOG="/root/.openclaw/logs/embedding-health.log"
STATE_FILE="/root/.openclaw/embedding-health-state.json"
ALERT_THRESHOLD=3
COMPOSE="docker compose -f /root/openclaw/docker-compose.yml"
mkdir -p "$(dirname "$LOG")"

FAILURES=0
if [ -f "$STATE_FILE" ]; then
  FAILURES=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('consecutive_failures',0))" 2>/dev/null || echo 0)
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PROBLEMS=""

# --- Probe 1: Ollama embeddings from inside the container ---
EMB=$($COMPOSE exec -T openclaw-gateway node -e "
(async () => {
  try {
    const r = await fetch('http://host.docker.internal:11434/v1/embeddings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'nomic-embed-text', input: 'health check' })
    });
    const j = await r.json();
    console.log(r.status === 200 && j.data && j.data[0].embedding.length > 0 ? 'ok' : 'bad:' + r.status);
  } catch(e) { console.log('unreachable'); }
})();
" 2>/dev/null | tail -1 || echo "exec-failed")
[ "$EMB" = "ok" ] || PROBLEMS="${PROBLEMS}ollama-embeddings=$EMB "

# --- Probe 2: vendored qmd in container ---
QMD=$($COMPOSE exec -T openclaw-gateway /home/node/.openclaw/vendor/qmd/node_modules/.bin/qmd --version 2>/dev/null | head -1 || echo "missing")
case "$QMD" in qmd*) : ;; *) PROBLEMS="${PROBLEMS}qmd=$QMD " ;; esac

# --- Probe 3: memory-core enabled in config ---
MEMCORE=$(python3 -c "
import json
cfg=json.load(open('/root/.openclaw/openclaw.json'))
pl=cfg.get('plugins',{})
ok = pl.get('entries',{}).get('memory-core',{}).get('enabled') is True and 'memory-core' in pl.get('allow',[])
print('ok' if ok else 'disabled')
" 2>/dev/null || echo "config-unreadable")
[ "$MEMCORE" = "ok" ] || PROBLEMS="${PROBLEMS}memory-core=$MEMCORE "

if [ -z "$PROBLEMS" ]; then
  echo "[$TS] MEMORY CHAIN: OK (ollama+qmd+memory-core)" >> "$LOG"
  if [ "$FAILURES" -ge "$ALERT_THRESHOLD" ]; then
    echo "[$TS] RECOVERED after $FAILURES consecutive failures" >> "$LOG"
    $COMPOSE exec -T openclaw-gateway \
      openclaw message send --channel discord --account robert --target ops-alerts \
      -m "Memory chain RECOVERED after ${FAILURES} failures ($(( FAILURES * 30 )) min downtime)" 2>/dev/null | grep -v "level=warning" || true
  fi
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
  echo "[$TS] MEMORY CHAIN: DEGRADED (${PROBLEMS}) — failure #${FAILURES}" >> "$LOG"
  echo '{"consecutive_failures":'"$FAILURES"',"last_status":"'"$PROBLEMS"'","last_check":"'"$TS"'"}' > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
  # Alert ONLY at threshold crossing (state change), not every failure
  if [ "$FAILURES" -eq "$ALERT_THRESHOLD" ]; then
    echo "[$TS] ALERT: ${FAILURES} consecutive failures — notifying" >> "$LOG"
    issue-log "Memory chain degraded: ${PROBLEMS}. memory_search will fail for all agents. Probes: ollama-from-container, vendored qmd, memory-core plugin. Last fix 2026-06-11: vendor qmd + enable memory-core + Ollama baseUrl." --source embedding-health-check --severity high 2>/dev/null || true
    $COMPOSE exec -T openclaw-gateway \
      openclaw message send --channel discord --account robert --target ops-alerts \
      -m "ALERT: memory chain degraded for ${FAILURES} consecutive checks ($(( FAILURES * 30 )) min): ${PROBLEMS}" 2>/dev/null | grep -v "level=warning" || true
    /root/.openclaw/scripts/ops-db.py incident open "Memory chain extended outage" \
      --severity high --desc "${PROBLEMS} — ${FAILURES} consecutive failures" 2>/dev/null || true
  fi
fi
