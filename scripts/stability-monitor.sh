#!/bin/bash
# Alignment: 5-minute host monitor that alerts on Telegram only when system state changes.
# Role: Check gateway, executor, Bridge, disk, and memory health without spamming repeat failures.
# Dependencies: Reads Docker/container status, Bridge HTTP health, disk and memory stats,
# ops.db presence, and prior state from /root/.openclaw/stability-state.json; writes log/state
# under /root/.openclaw and sends Telegram alerts via `telegram-resolve` + messaging tools.
# Key patterns: Delta-based restart detection compares current restart counters to saved state;
# notification flow is stateful and change-only, so healthy-to-bad and bad-to-changed transitions
# alert once while repeated unchanged failures stay quiet; exit codes distinguish monitor failure
# from monitored-system failure for cron visibility.
# Reference: /root/.openclaw/docs/policy-context-injection.md

set -uo pipefail

STATE_FILE="/root/.openclaw/stability-state.json"
LOG="/root/.openclaw/logs/stability-monitor.log"
OPS_DB="/root/.openclaw/ops.db"
TELEGRAM_TARGET=$(telegram-resolve robert)
DISCORD_OPS_ALERTS="1477754571697688627"
CONTAINER="openclaw-openclaw-gateway-1"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> "$LOG"; }

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

open_gateway_downtime_incident() {
  local STATUS="$1"
  local STATUS_ESC DESC_ESC
  STATUS_ESC=$(sql_escape "$STATUS")
  DESC_ESC=$(sql_escape "Gateway container status: ${STATUS}. Opened by stability-monitor.sh after docker inspect reported a non-running state.")
  sqlite3 "$OPS_DB" "
    INSERT INTO incidents (provider, severity, title, description, meta)
    SELECT
      'gateway',
      'high',
      'Gateway downtime',
      '${DESC_ESC}',
      json_object(
        'source', 'stability-monitor.sh',
        'container', '${CONTAINER}',
        'detected_status', '${STATUS_ESC}'
      )
    WHERE NOT EXISTS (
      SELECT 1
      FROM incidents
      WHERE closed_at IS NULL
        AND provider = 'gateway'
        AND title = 'Gateway downtime'
    );
  " >/dev/null 2>&1 || log "INCIDENT: failed to open gateway downtime incident"
}

resolve_gateway_downtime_incident() {
  local RESOLUTION="$1"
  local RESOLUTION_ESC
  RESOLUTION_ESC=$(sql_escape "$RESOLUTION")
  sqlite3 "$OPS_DB" "
    UPDATE incidents
    SET closed_at = strftime('%Y-%m-%dT%H:%M:%SZ','now'),
        resolution = '${RESOLUTION_ESC}'
    WHERE closed_at IS NULL
      AND provider = 'gateway'
      AND title = 'Gateway downtime';
  " >/dev/null 2>&1 || log "INCIDENT: failed to resolve gateway downtime incident"
}

# Direct Telegram send — bypasses gateway entirely (works when gateway is down)
telegram_direct() {
  local MSG="$1"
  local TOKEN
  TOKEN=$(grep '^TELEGRAM_BOT_TOKEN_ROBERT=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  [ -z "$TOKEN" ] && TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
  [ -z "$TOKEN" ] && { log "telegram_direct: no token found"; return 1; }
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_TARGET}" \
    -d text="${MSG}" \
    -d parse_mode=Markdown >/dev/null 2>&1
}

CHECK_ERRORS=0

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
  echo '{"gateway":"unknown","telegram":"unknown","discord":"unknown","rate_limited":false,"last_alert":"","consecutive_failures":0}' > "$STATE_FILE"
fi

PREV_STATE=$(cat "$STATE_FILE") || { log "CHECK FAILED: read state file"; CHECK_ERRORS=$((CHECK_ERRORS+1)); PREV_STATE='{}'; }
ALERTS=""
RECOVERED=""
GATEWAY_WAS_DOWN_THIS_RUN=0
RECOVERY_SOURCE=""

# Check 1: Is the gateway container running?
CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' "$CONTAINER" 2>/dev/null) || { log "CHECK FAILED: docker inspect"; CHECK_ERRORS=$((CHECK_ERRORS+1)); CONTAINER_STATUS="missing"; }
if [ "$CONTAINER_STATUS" != "running" ]; then
  GATEWAY_WAS_DOWN_THIS_RUN=1
  RECOVERY_SOURCE="$CONTAINER_STATUS"
  ALERTS="${ALERTS}Gateway container is ${CONTAINER_STATUS}. "
  log "ALERT: Gateway $CONTAINER_STATUS"
  open_gateway_downtime_incident "$CONTAINER_STATUS"

  # Auto-restart gateway with cooldown (10 min between attempts)
  COOLDOWN_FILE="/root/.openclaw/.gateway-restart-cooldown"
  COOLDOWN_SECONDS=600
  LAST_RESTART=$(stat -c %Y "$COOLDOWN_FILE" 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s)
  if [ $((NOW_EPOCH - LAST_RESTART)) -gt $COOLDOWN_SECONDS ]; then
    log "AUTO-RESTART: Attempting gateway restart"
    touch "$COOLDOWN_FILE"
    docker compose -f /root/openclaw/docker-compose.yml up -d openclaw-gateway 2>/dev/null
    sleep 12
    NEW_STATUS=$(docker inspect --format '{{.State.Status}}' "$CONTAINER" 2>/dev/null)
    if [ "$NEW_STATUS" = "running" ]; then
      log "AUTO-RESTART: Gateway recovered"
      telegram_direct "Auto-restart: Gateway recovered. All services resuming."
      RECOVERED="${RECOVERED}Gateway auto-restarted. "
      CONTAINER_STATUS="running"
    else
      log "AUTO-RESTART: Gateway failed to restart (status: $NEW_STATUS)"
      telegram_direct "ALERT: Gateway auto-restart FAILED (status: $NEW_STATUS). Manual intervention needed."
    fi
  else
    log "AUTO-RESTART: Cooldown active (last attempt $((NOW_EPOCH - LAST_RESTART))s ago)"
  fi
fi

# Check 2: Is the gateway healthy? (only if container is running)
if [ "$CONTAINER_STATUS" = "running" ]; then
  HEALTH=$(docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw health 2>/dev/null | grep -v "level=warning") || { log "CHECK FAILED: openclaw health"; CHECK_ERRORS=$((CHECK_ERRORS+1)); HEALTH="HEALTH_CHECK_FAILED"; }

  # Telegram bot status
  if echo "$HEALTH" | grep -qE "Telegram: (ok|configured|connected|running)"; then
    if echo "$PREV_STATE" | python3 -c "import json,sys; s=json.load(sys.stdin); exit(0 if s.get('telegram')=='down' else 1)" 2>/dev/null; then
      RECOVERED="${RECOVERED}Telegram bot recovered. "
    fi
  else
    ALERTS="${ALERTS}Telegram bot is DOWN. "
    log "ALERT: Telegram down"
  fi

  # Discord bot status
  if echo "$HEALTH" | grep -qE "Discord: (ok|configured|connected|running)"; then
    if echo "$PREV_STATE" | python3 -c "import json,sys; s=json.load(sys.stdin); exit(0 if s.get('discord')=='down' else 1)" 2>/dev/null; then
      RECOVERED="${RECOVERED}Discord bot recovered. "
    fi
  else
    ALERTS="${ALERTS}Discord bot is DOWN. "
    log "ALERT: Discord down"
  fi

  # Check 3: Rate limit storm detection (>10 errors in last 5 min)
  ERROR_COUNT=$(docker compose -f /root/openclaw/docker-compose.yml logs --since=5m openclaw-gateway 2>&1 | grep -c "rate limit reached") || ERROR_COUNT=0
  if [ "$ERROR_COUNT" -gt 10 ]; then
    ALERTS="${ALERTS}Rate limit storm: ${ERROR_COUNT} rate-limit errors in 5 min. "
    log "ALERT: Rate limit storm ($ERROR_COUNT errors)"
  fi

  # Check 4a: Codex OAuth failure detection
  CODEX_ERRORS=$(docker compose -f /root/openclaw/docker-compose.yml logs --since=5m openclaw-gateway 2>&1 | grep -ci "token refresh failed\|oauth token refresh failed\|openai-codex.*401\|openai-codex.*unauthorized") || CODEX_ERRORS=0
  if [ "$CODEX_ERRORS" -gt 0 ]; then
    # Only trigger reauth if no recent codex-reauth task exists (pending, in_progress, OR blocked in last 2h)
    # Previous bug: only checked pending/in_progress, so blocked reauths were invisible → 20 spawned overnight
    PENDING_REAUTH=$(python3 -c "
import sqlite3, json
conn = sqlite3.connect('$OPS_DB')
conn.execute('PRAGMA busy_timeout=5000')
rows = conn.execute(\"\"\"SELECT meta FROM tasks
    WHERE status IN ('pending','in_progress','blocked')
    AND meta IS NOT NULL
    AND created_at > datetime('now', '-2 hours')\"\"\").fetchall()
count = sum(1 for r in rows if 'codex-reauth' in (json.loads(r[0]).get('host_op','') if r[0] else ''))
print(count)
conn.close()
" 2>/dev/null) || PENDING_REAUTH=0
    if [ "$PENDING_REAUTH" = "0" ]; then
      # Step 1: Try sync first (no human needed — copies host CLI tokens to gateway)
      log "ALERT: Codex OAuth failure detected — attempting auto-sync"
      SYNC_RESULT=$(/root/.openclaw/scripts/sync-codex-auth.sh 2>&1) || true
      if echo "$SYNC_RESULT" | grep -q "Tokens synced"; then
        log "AUTO-HEALED: Codex tokens synced from host CLI to gateway (no human needed)"
        ALERTS="${ALERTS}Codex OAuth auto-healed — tokens synced from host CLI. "
      else
        # Step 2: Sync failed (host tokens also expired) — send reauth link to Telegram
        python3 -c "
import sqlite3
conn = sqlite3.connect('$OPS_DB')
conn.execute('PRAGMA busy_timeout=5000')
conn.execute('''INSERT INTO tasks (agent, task, meta, urgency, status) VALUES (?, ?, ?, ?, 'pending')''',
    ('stability-monitor', 'Codex reauth (auto-sync failed, need human auth)', '{\"host_op\":\"codex-reauth-telegram\",\"chat_id\":\"8561305605\",\"auto\":true}', 'critical'))
conn.commit()
conn.close()
" 2>/dev/null
        ALERTS="${ALERTS}Codex OAuth errors detected — auto-sync failed, reauth link sent to Telegram. "
        log "ALERT: Codex auto-sync failed, reauth-telegram task created"
      fi
    else
      log "INFO: Codex OAuth errors detected but reauth already pending"
    fi
  fi

  # Check 4: Crash loop detection — compare against stored baseline, not zero
  # Docker RestartCount is cumulative lifetime. We detect NEW restarts since last check.
  RESTART_COUNT=$(docker inspect --format '{{.RestartCount}}' "$CONTAINER" 2>/dev/null) || { log "CHECK FAILED: docker restart count"; CHECK_ERRORS=$((CHECK_ERRORS+1)); RESTART_COUNT=0; }
  PREV_RESTARTS=$(echo "$PREV_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('restart_count',0))" 2>/dev/null) || PREV_RESTARTS=0
  NEW_RESTARTS=$((RESTART_COUNT - PREV_RESTARTS))
  if [ "$NEW_RESTARTS" -gt 3 ]; then
    ALERTS="${ALERTS}Gateway in restart loop (${NEW_RESTARTS} new restarts since last check). "
    log "ALERT: Restart loop ($NEW_RESTARTS new, $RESTART_COUNT total)"
  fi
fi

# Check 5: Memory pressure — detect AND remediate
PRESSURE_FLAG="/root/.openclaw/pressure-mode"
RELIEF_SCRIPT="/root/.openclaw/scripts/pressure-relief.sh"
MEM_AVAIL_MB=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo) || { log "CHECK FAILED: meminfo"; CHECK_ERRORS=$((CHECK_ERRORS+1)); MEM_AVAIL_MB=9999; }

if [ "$MEM_AVAIL_MB" -lt 500 ]; then
  MEM_TOTAL_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
  SWAP_USED=$(awk '/SwapTotal/ {t=$2} /SwapFree/ {f=$2} END {printf "%d", (t-f)/1024}' /proc/meminfo)
  KSWAPD_CPU=$(ps -eo comm,%cpu --no-headers | awk '/kswapd/ {print $2}') || KSWAPD_CPU="?"

  # Determine tier and run pressure relief
  if [ "$MEM_AVAIL_MB" -lt 200 ]; then
    RELIEF_TIER=3
    ALERTS="${ALERTS}CRITICAL memory: ${MEM_AVAIL_MB}MB available of ${MEM_TOTAL_MB}MB. Auto-relief TIER 3 triggered. "
  elif [ "$MEM_AVAIL_MB" -lt 300 ]; then
    RELIEF_TIER=2
    ALERTS="${ALERTS}HIGH memory pressure: ${MEM_AVAIL_MB}MB available of ${MEM_TOTAL_MB}MB. Auto-relief TIER 2 triggered. "
  else
    RELIEF_TIER=1
    ALERTS="${ALERTS}Memory pressure: ${MEM_AVAIL_MB}MB available of ${MEM_TOTAL_MB}MB. Auto-relief TIER 1 triggered. "
  fi
  ALERTS="${ALERTS}(swap: ${SWAP_USED}MB, kswapd0: ${KSWAPD_CPU}% CPU). "
  log "ALERT: Memory ${MEM_AVAIL_MB}MB — triggering pressure-relief tier $RELIEF_TIER"

  # Run pressure relief (local bash, no dependencies)
  if [ -x "$RELIEF_SCRIPT" ]; then
    RELIEF_OUT=$("$RELIEF_SCRIPT" "$RELIEF_TIER" 2>&1) || true
    log "RELIEF: $RELIEF_OUT"
    ALERTS="${ALERTS}Relief result: ${RELIEF_OUT}. "
  else
    log "ERROR: pressure-relief.sh not found or not executable"
  fi
fi

# Check 5a: Swap usage > 75% means the safety net is running out
SWAP_TOTAL_KB=$(awk '/SwapTotal/ {print $2}' /proc/meminfo) || SWAP_TOTAL_KB=0
if [ "$SWAP_TOTAL_KB" -gt 0 ]; then
  SWAP_FREE_KB=$(awk '/SwapFree/ {print $2}' /proc/meminfo)
  SWAP_USED_PCT=$(( (SWAP_TOTAL_KB - SWAP_FREE_KB) * 100 / SWAP_TOTAL_KB ))
  if [ "$SWAP_USED_PCT" -gt 75 ]; then
    ALERTS="${ALERTS}Swap ${SWAP_USED_PCT}% used — safety net nearly exhausted. "
    log "ALERT: Swap ${SWAP_USED_PCT}% used"
    # Escalate to tier 2 relief if not already triggered
    if [ "$MEM_AVAIL_MB" -ge 500 ] && [ -x "$RELIEF_SCRIPT" ]; then
      RELIEF_OUT=$("$RELIEF_SCRIPT" 2 2>&1) || true
      log "RELIEF (swap-triggered): $RELIEF_OUT"
    fi
  fi
fi

# Check 5b: CPU load average > 3x vCPU count = sustained saturation
NCPU=$(nproc) || NCPU=2
LOAD_1M=$(awk '{printf "%d", $1}' /proc/loadavg) || LOAD_1M=0
LOAD_THRESHOLD=$((NCPU * 3))
if [ "$LOAD_1M" -gt "$LOAD_THRESHOLD" ]; then
  LOAD_FULL=$(cut -d' ' -f1-3 /proc/loadavg)
  ALERTS="${ALERTS}CPU saturated: load avg ${LOAD_FULL} on ${NCPU} vCPUs. "
  log "ALERT: CPU saturated — load ${LOAD_FULL} on ${NCPU} cores"
  # CPU saturation with memory pressure = enable pressure mode to defer agent work
  if [ ! -f "$PRESSURE_FLAG" ] && [ -x "$RELIEF_SCRIPT" ]; then
    "$RELIEF_SCRIPT" 2 >/dev/null 2>&1 || true
    log "RELIEF: CPU saturation triggered tier 2 (pressure mode enabled)"
  fi
fi

# Check 5c: Stuck task detection — in_progress for >15 min = something is hung
STUCK_TASKS=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='in_progress' AND updated_at < datetime('now', '-15 minutes');" 2>/dev/null) || STUCK_TASKS=0
if [ "$STUCK_TASKS" -gt 0 ]; then
  STUCK_IDS=$(sqlite3 "$OPS_DB" "SELECT id FROM tasks WHERE status='in_progress' AND updated_at < datetime('now', '-15 minutes') LIMIT 5;" 2>/dev/null)
  ALERTS="${ALERTS}${STUCK_TASKS} task(s) stuck in_progress >15 min (IDs: ${STUCK_IDS}). FIX: unstick via Bridge or cancel. "
  log "ALERT: $STUCK_TASKS stuck in_progress tasks: $STUCK_IDS"
  # Auto-cancel tasks stuck >30 min (they're dead)
  sqlite3 "$OPS_DB" "
    UPDATE tasks SET status='cancelled',
      outcome=COALESCE(outcome,'') || ' [auto-cancelled: stuck in_progress >30 min, detected by stability-monitor]',
      updated_at=datetime('now')
    WHERE status='in_progress' AND updated_at < datetime('now', '-30 minutes');
  " 2>/dev/null
fi

# Check 5c: Pressure mode recovery — clear flag when resources are healthy again
if [ -f "$PRESSURE_FLAG" ] && [ "$MEM_AVAIL_MB" -gt 1000 ] && [ "$LOAD_1M" -le "$((NCPU * 2))" ]; then
  rm -f "$PRESSURE_FLAG"
  log "RECOVERED: Pressure mode cleared (${MEM_AVAIL_MB}MB available, load ${LOAD_1M})"
  RECOVERED="${RECOVERED}Pressure mode cleared — resources healthy. "
fi

# Check 6: Ollama (embedding service)
if ! curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
  ALERTS="${ALERTS}Ollama is DOWN (embeddings broken). "
  log "ALERT: Ollama down"
fi

# Check 7: Disk space — detect AND remediate
DISK_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%') || { log "CHECK FAILED: df"; CHECK_ERRORS=$((CHECK_ERRORS+1)); DISK_PCT=0; }
DISK_FREE_GB=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G') || DISK_FREE_GB="?"

if [ "$DISK_PCT" -gt 75 ]; then
  if [ "$DISK_PCT" -gt 90 ]; then
    DISK_TIER=3
    ALERTS="${ALERTS}CRITICAL disk: ${DISK_PCT}% used (${DISK_FREE_GB}GB free). Auto-relief DISK TIER 3 triggered. "
  elif [ "$DISK_PCT" -gt 85 ]; then
    DISK_TIER=2
    ALERTS="${ALERTS}HIGH disk pressure: ${DISK_PCT}% used (${DISK_FREE_GB}GB free). Auto-relief DISK TIER 2 triggered. "
  else
    DISK_TIER=1
    ALERTS="${ALERTS}Disk pressure: ${DISK_PCT}% used (${DISK_FREE_GB}GB free). Auto-relief DISK TIER 1 triggered. "
  fi
  log "ALERT: Disk ${DISK_PCT}% — triggering disk relief tier $DISK_TIER"

  if [ -x "$RELIEF_SCRIPT" ]; then
    DISK_RELIEF_OUT=$("$RELIEF_SCRIPT" "$DISK_TIER" --disk 2>&1) || true
    log "DISK RELIEF: $DISK_RELIEF_OUT"
    ALERTS="${ALERTS}Disk relief: ${DISK_RELIEF_OUT}. "
  fi
fi

# Check 8: Tap daemon — standalone check (not gated on gateway recovery)
# Use exact process match to avoid false positives from Claude Code bash wrappers
TAP_RUNNING=$(pgrep -x -f "python3 tap-daemon.py" >/dev/null 2>&1 && echo "yes" || echo "no")
if [ "$TAP_RUNNING" = "no" ]; then
  # Double-check with ps to be certain
  TAP_RUNNING=$(ps aux | grep "[p]ython3 tap-daemon.py" | grep -v grep | wc -l)
  if [ "$TAP_RUNNING" = "0" ]; then
    log "ALERT: Tap daemon is DOWN — auto-restarting"
    cd /root/.openclaw/scripts && nohup python3 tap-daemon.py >> /root/.openclaw/logs/tap-daemon.log 2>&1 &
    sleep 2
    if pgrep -f "tap-daemon.py" >/dev/null 2>&1; then
      RECOVERED="${RECOVERED}Tap daemon auto-restarted. "
      log "RECOVERED: Tap daemon restarted (PID $(pgrep -f tap-daemon.py | head -1))"
    else
      ALERTS="${ALERTS}Tap daemon DOWN and restart FAILED. "
      log "ALERT: Tap daemon restart failed"
    fi
  fi
fi

# Check 9: host-ops-executor — auto-restart via systemd
if ! ps aux | grep "[h]ost-ops-executor" | grep -qv grep; then
  log "ALERT: host-ops-executor is DOWN — auto-restarting via systemd"
  systemctl restart openclaw-host-ops.service 2>/dev/null
  sleep 3
  if systemctl is-active openclaw-host-ops.service >/dev/null 2>&1; then
    RECOVERED="${RECOVERED}host-ops-executor auto-restarted via systemd. "
    log "RECOVERED: host-ops-executor restarted"
  else
    ALERTS="${ALERTS}host-ops-executor DOWN and systemd restart FAILED. "
    log "ALERT: host-ops-executor restart failed (systemd status: $(systemctl is-active openclaw-host-ops.service 2>/dev/null))"
  fi
fi

# Check 10: backbone-listener
if ! ps aux | grep "[b]ackbone-listener.py" | grep -qv grep; then
  log "ALERT: backbone-listener is DOWN — auto-restarting"
  cd /root/.openclaw/scripts && nohup python3 backbone-listener.py >> /root/.openclaw/logs/backbone-listener.log 2>&1 &
  sleep 2
  if ps aux | grep "[b]ackbone-listener.py" | grep -qv grep >/dev/null; then
    RECOVERED="${RECOVERED}backbone-listener auto-restarted. "
    log "RECOVERED: backbone-listener restarted"
  else
    ALERTS="${ALERTS}backbone-listener DOWN and restart FAILED. "
    log "ALERT: backbone-listener restart failed"
  fi
fi

# Check 11: relay-handoff-watcher
if ! ps aux | grep "[r]elay-handoff-watcher.py" | grep -qv grep; then
  log "ALERT: relay-handoff-watcher is DOWN — auto-restarting"
  cd /root/.openclaw/scripts && nohup python3 relay-handoff-watcher.py >> /root/.openclaw/logs/relay-handoff-watcher.log 2>&1 &
  sleep 2
  if ps aux | grep "[r]elay-handoff-watcher.py" | grep -qv grep >/dev/null; then
    RECOVERED="${RECOVERED}relay-handoff-watcher auto-restarted. "
    log "RECOVERED: relay-handoff-watcher restarted"
  else
    ALERTS="${ALERTS}relay-handoff-watcher DOWN and restart FAILED. "
    log "ALERT: relay-handoff-watcher restart failed"
  fi
fi

# Check 12: telegram-listener
if ! ps aux | grep "[t]elegram-listener.py" | grep -qv grep; then
  ALERTS="${ALERTS}telegram-listener is DOWN (cron should restart). "
  log "ALERT: telegram-listener down"
fi

# Check 13: Bridge dashboards
# Bridge runs as openclaw-bridge-dev (ports 8082+8083+8084 via BRIDGE_PORTS env)
# NEVER use openclaw-bridge.service (old, single-port — disabled 2026-04-22 after overnight crash-loop)
# Why: two services fighting for port 8082 caused all-night crash-loop + Relay spam
for SVC in openclaw-bridge-dev; do
  if ! systemctl is-active --quiet "$SVC" 2>/dev/null; then
    # Try auto-fix: kill any stale python dashboard-api.py holding ports, then restart
    STALE_PIDS=$(fuser 8082/tcp 2>/dev/null | tr -s ' ')
    if [ -n "$STALE_PIDS" ]; then
      log "Bridge port 8082 held by stale PID(s): $STALE_PIDS — killing before restart"
      kill -9 $STALE_PIDS 2>/dev/null
      sleep 2
    fi
    # Also ensure old bridge service isn't running (it was disabled but check anyway)
    systemctl stop openclaw-bridge.service 2>/dev/null
    systemctl restart "$SVC" 2>/dev/null
    sleep 3
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
      RECOVERED="${RECOVERED}Bridge auto-recovered (killed stale port holder + restarted). "
      log "RECOVERY: Bridge auto-recovered"
    else
      ALERTS="${ALERTS}${SVC} is DOWN (auto-restart failed). "
      log "ALERT: ${SVC} down — auto-restart failed"
    fi
  fi
done

# State-change recovery: gateway was down, now running → fire recovery hook ONCE
PREV_GATEWAY=$(echo "$PREV_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('gateway','unknown'))" 2>/dev/null) || PREV_GATEWAY="unknown"
if [ "$CONTAINER_STATUS" = "running" ] && { [ "$GATEWAY_WAS_DOWN_THIS_RUN" = "1" ] || { [ "$PREV_GATEWAY" != "running" ] && [ "$PREV_GATEWAY" != "unknown" ]; }; }; then
  if [ -n "$RECOVERY_SOURCE" ]; then
    log "RECOVERY HOOK: Gateway state changed from $RECOVERY_SOURCE -> running"
    resolve_gateway_downtime_incident "Gateway recovered after status ${RECOVERY_SOURCE}; recovery hook marked the downtime resolved."
  else
    log "RECOVERY HOOK: Gateway state changed from $PREV_GATEWAY -> running"
    resolve_gateway_downtime_incident "Gateway recovered after status ${PREV_GATEWAY}; recovery hook marked the downtime resolved."
  fi

  # 1. Reset stuck in_progress tasks that were dispatched during downtime
  RESET_COUNT=$(sqlite3 /root/.openclaw/ops.db "
    UPDATE tasks SET status='pending', updated_at=datetime('now')
    WHERE status='in_progress'
    AND updated_at < datetime('now', '-5 minutes');
    SELECT changes();
  " 2>/dev/null) || RESET_COUNT=0
  [ "$RESET_COUNT" -gt 0 ] && log "RECOVERY: Reset $RESET_COUNT stuck in_progress tasks to pending"

  # 2. Restart tap daemon if down
  if ! pgrep -f "tap-daemon.py" >/dev/null 2>&1; then
    cd /root/.openclaw/scripts && nohup python3 tap-daemon.py >> /root/.openclaw/logs/tap-daemon.log 2>&1 &
    log "RECOVERY: Restarted tap daemon"
  fi

  # 3. Write recovery event (state-change, not spam — Tactyl pattern)
  sqlite3 /root/.openclaw/ops.db "
    INSERT INTO kv (key, value, updated_at) VALUES ('gateway_recovery_event', json_object(
      'ts', datetime('now'),
      'prev_state', '$PREV_GATEWAY',
      'tasks_reset', $RESET_COUNT
    ), datetime('now'))
    ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at;
  " 2>/dev/null

  RECOVERED="${RECOVERED}Gateway recovered from $PREV_GATEWAY (reset $RESET_COUNT tasks). "
fi

# Update state
TELEGRAM_STATE="up"
DISCORD_STATE="up"
RATE_LIMITED="false"
FAILURES=$(echo "$PREV_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('consecutive_failures',0))" 2>/dev/null) || FAILURES=0

if echo "$ALERTS" | grep -q "Telegram"; then TELEGRAM_STATE="down"; fi
if echo "$ALERTS" | grep -q "Discord"; then DISCORD_STATE="down"; fi
if echo "$ALERTS" | grep -q "Rate limit"; then RATE_LIMITED="true"; fi

if [ -n "$ALERTS" ]; then
  FAILURES=$((FAILURES + 1))
else
  FAILURES=0
fi

python3 -c "
import json
state = {
    'gateway': '$CONTAINER_STATUS',
    'telegram': '$TELEGRAM_STATE',
    'discord': '$DISCORD_STATE',
    'rate_limited': True if '$RATE_LIMITED' == 'true' else False,
    'last_check': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'consecutive_failures': $FAILURES,
    'restart_count': $RESTART_COUNT
}
if '$ALERTS':
    state['last_alert'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
    state['last_alert_text'] = '''$ALERTS'''
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
"

# Helper: send alerts — always sends to Telegram (direct API), Discord only if gateway is up
send_alert() {
  local MSG="$1"
  local ALERT_TYPE="${2:-general}"
  local HOST="${3:-$(hostname)}"

  # ALWAYS send via direct Telegram (no gateway dependency)
  telegram_direct "$MSG"

  # If gateway is running, also send rich Discord message with buttons
  if [ "$CONTAINER_STATUS" = "running" ]; then
    docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway \
      openclaw message send --channel discord --target "$DISCORD_OPS_ALERTS" \
      --message "$MSG" 2>/dev/null | grep -v "level=warning" | tail -1
  fi
}

# Send alerts (with dedup — only send on state CHANGE or every 30 min for ongoing)
if [ -n "$ALERTS" ]; then
  PREV_ALERT=$(echo "$PREV_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('last_alert_text',''))" 2>/dev/null) || PREV_ALERT=""
  PREV_ALERT_TIME=$(echo "$PREV_STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('last_alert',''))" 2>/dev/null) || PREV_ALERT_TIME=""
  MINUTES_SINCE_ALERT=999
  if [ -n "$PREV_ALERT_TIME" ]; then
    MINUTES_SINCE_ALERT=$(python3 -c "
from datetime import datetime, timezone
try:
    t=datetime.fromisoformat('$PREV_ALERT_TIME'.replace('Z','+00:00'))
    print(int((datetime.now(timezone.utc)-t).total_seconds()/60))
except: print(999)
" 2>/dev/null) || MINUTES_SINCE_ALERT=999
  fi
  # Send if: (1) new alert text, (2) first alert, or (3) 30+ min since last send
  SHOULD_SEND="no"
  if [ "$ALERTS" != "$PREV_ALERT" ]; then SHOULD_SEND="yes"; fi
  if [ "$FAILURES" -le 1 ]; then SHOULD_SEND="yes"; fi
  if [ "$MINUTES_SINCE_ALERT" -ge 30 ]; then SHOULD_SEND="yes"; fi

  if [ "$SHOULD_SEND" = "yes" ]; then
  # Build resource snapshot for context
  MEM_SNAP="RAM: $(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)MB free"
  SWAP_SNAP=""
  if [ "$(awk '/SwapTotal/ {print $2}' /proc/meminfo)" -gt 0 ] 2>/dev/null; then
    SWAP_SNAP=" | Swap: $(awk '/SwapTotal/ {t=$2} /SwapFree/ {f=$2} END {printf "%d", (t-f)/1024}' /proc/meminfo)MB used"
  fi
  LOAD_SNAP="Load: $(cut -d' ' -f1-3 /proc/loadavg)"
  PRESSURE_SNAP=""
  if [ -f "$PRESSURE_FLAG" ]; then
    PRESSURE_SNAP=" | PRESSURE MODE ACTIVE"
  fi

  MSG="System Alert

${ALERTS}
${MEM_SNAP}${SWAP_SNAP} | ${LOAD_SNAP}${PRESSURE_SNAP}
Consecutive failures: ${FAILURES}
Checked: $(date -u +%H:%M) UTC"

  send_alert "$MSG" "general" "$(hostname)"
  log "Alert sent to Discord"
  else
    log "Alert suppressed (same as last, ${MINUTES_SINCE_ALERT}m since last send, failures=$FAILURES)"
  fi
fi

# Send recovery notices
if [ -n "$RECOVERED" ]; then
  MSG="Recovery: ${RECOVERED}
Checked: $(date -u +%H:%M) UTC"

  send_alert "$MSG" "general" "$(hostname)"
  log "Recovery notice sent to Discord"
fi

# Quiet when healthy
if [ -z "$ALERTS" ] && [ -z "$RECOVERED" ]; then
  log "OK: All systems healthy"
fi

# Maintenance: keep VS Code expendable for OOM killer (resets on process restart)
for pid in $(pgrep -f "vscode-server" 2>/dev/null); do
  echo 300 > /proc/$pid/oom_score_adj 2>/dev/null
done

# Exit codes: 2=monitoring broken, 1=alerts found, 0=all healthy
[ "$CHECK_ERRORS" -gt 0 ] && exit 2
[ -n "$ALERTS" ] && exit 1
exit 0
