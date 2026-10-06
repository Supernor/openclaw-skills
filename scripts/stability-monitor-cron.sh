#!/usr/bin/env bash
# Guarded cron entry for stability-monitor.sh. It clears stale flock holders
# before taking the lock, because a hung monitor can otherwise blind all future
# five-minute checks.

set -uo pipefail

LOCK="/tmp/cron-stability-monitor.lock"
LOG="/root/.openclaw/logs/stability-monitor.log"
MAX_LOCK_AGE_SECONDS=900

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> "$LOG"
}

mission_now() {
  local TEXT="$1"
  python3 - "$TEXT" <<'PY' >/dev/null 2>&1 || true
import datetime, json, os, sys
path = "/root/.openclaw/mission-now-activity.jsonl"
text = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)
row = {
    "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "text": text[:320],
}
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(row, ensure_ascii=False) + "\n")
PY
}

lock_pids() {
  fuser "$LOCK" 2>/dev/null | tr -s ' ' '\n' | sed '/^$/d'
}

clear_stale_lock_if_needed() {
  [ -e "$LOCK" ] || return 0
  local mtime now age pids alive
  mtime=$(stat -c %Y "$LOCK" 2>/dev/null || echo 0)
  now=$(date +%s)
  age=$((now - mtime))
  [ "$age" -le "$MAX_LOCK_AGE_SECONDS" ] && return 0

  pids=$(lock_pids || true)
  [ -n "$pids" ] || return 0

  log "STALE LOCK: stability-monitor lock age=${age}s held by PID(s): $(echo "$pids" | tr '\n' ' ')"
  mission_now "stability-monitor: cleared stale cron lock held for ${age}s"
  echo "$pids" | xargs -r kill 2>/dev/null || true
  sleep 5
  alive=$(echo "$pids" | xargs -r -n1 sh -c 'kill -0 "$1" 2>/dev/null && echo "$1"' sh 2>/dev/null || true)
  if [ -n "$alive" ]; then
    log "STALE LOCK: force-killing remaining PID(s): $(echo "$alive" | tr '\n' ' ')"
    echo "$alive" | xargs -r kill -9 2>/dev/null || true
  fi
}

clear_stale_lock_if_needed

exec flock --close -n "$LOCK" /bin/bash -c '/root/.openclaw/scripts/startup-guard.sh 180 && /root/.openclaw/scripts/cron-wrapper.sh "stability-monitor" /root/.openclaw/scripts/stability-monitor.sh'
