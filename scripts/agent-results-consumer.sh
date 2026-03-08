#!/usr/bin/env bash
# agent-results-consumer.sh — The "last mile" mailman
# Intent: Reliable [I05], Observable [I13].
# Polls ops.db agent_results for unconsumed rows, routes them, marks consumed.
# Runs as cron every 5 minutes.

set -eo pipefail

DB="/home/node/.openclaw/ops.db"
COMPOSE_DIR="/root/openclaw"
LOG="/root/.openclaw/logs/consumer.log"
mkdir -p "$(dirname "$LOG")"

_exec() {
  docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway "$@" 2>&1 | grep -v "level=warning"
}

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Get unconsumed IDs
IDS=$(_exec sqlite3 "$DB" "SELECT id FROM agent_results WHERE consumed = 0 ORDER BY created_at ASC LIMIT 50;" 2>/dev/null) || true

if [ -z "$IDS" ]; then
  exit 0
fi

mkdir -p /root/.openclaw/health
COUNT=0
for id in $IDS; do
  # Skip non-numeric
  [[ "$id" =~ ^[0-9]+$ ]] || continue

  # Get details for logging
  ROW=$(_exec sqlite3 "$DB" "SELECT task_id, from_agent, for_agent, type FROM agent_results WHERE id = $id;" 2>/dev/null) || continue
  IFS='|' read -r task_id from_agent for_agent type <<< "$ROW"

  # Log
  echo "[$(ts)] CONSUME id=$id task=$task_id from=$from_agent for=$for_agent type=$type" >> "$LOG"
  echo "{\"ts\":\"$(ts)\",\"source\":\"agent-result\",\"task_id\":\"$task_id\",\"from\":\"$from_agent\",\"for\":\"$for_agent\",\"type\":\"$type\"}" >> /root/.openclaw/health/buffer.jsonl 2>/dev/null || true

  # Mark consumed
  _exec sqlite3 "$DB" "UPDATE agent_results SET consumed = 1 WHERE id = $id;" 2>/dev/null || true

  COUNT=$((COUNT + 1))
done

if [ "$COUNT" -gt 0 ]; then
  echo "[$(ts)] Consumed $COUNT agent results" >> "$LOG"
fi

# Dead-letter check: flag results older than 24h that are STILL unconsumed after this run
STALE=$(_exec sqlite3 "$DB" "SELECT COUNT(*) FROM agent_results WHERE consumed = 0 AND datetime(created_at) < datetime('now', '-24 hours');" 2>/dev/null) || true
if [ -n "$STALE" ] && [ "$STALE" -gt 0 ]; then
  echo "[$(ts)] WARNING: $STALE unconsumed results older than 24h" >> "$LOG"
  mkdir -p /root/.openclaw/health
  echo "{\"ts\":\"$(ts)\",\"source\":\"consumer-deadletter\",\"stale_count\":$STALE}" >> /root/.openclaw/health/buffer.jsonl
  issue-log "Consumer: $STALE agent_results unconsumed >24h (dead letter)" --source consumer --severity high 2>/dev/null || true
fi
