#!/usr/bin/env bash
# system-troubleshoot.sh — Zero-token system diagnosis pointing at ACTUAL TRUTH.
# Every check reads LIVE state. Nothing assumed. Nothing cached. Nothing from yesterday.
# Updated: 2026-03-27 | Refresh: zero-token
# Self-improving: add checks as new failure modes are discovered.
# Sections: Processes, Systemd Guards, Gateway Probes, Tasks, Config, Engines, Crons, Bridge, Resources, Data

set -uo pipefail
OPS_DB="/root/.openclaw/ops.db"
OPENCLAW_JSON="/root/.openclaw/openclaw.json"
ISSUES=0
WARNINGS=0

issue() { ISSUES=$((ISSUES + 1)); echo ""; echo "ISSUE #$ISSUES: $1"; echo "  CAUSE: $2"; echo "  FIX: $3"; }
warn() { WARNINGS=$((WARNINGS + 1)); echo ""; echo "WARNING #$WARNINGS: $1"; }

echo "=== SYSTEM TROUBLESHOOT — $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# Return only real python worker PIDs for a given script basename.
# Matches: python3 script.py, python3 /path/to/script.py, /usr/bin/python3 script.py
python_worker_pids() {
  local pattern="$1"
  ps -ww -eo pid=,args= | awk -v pat="$pattern" '
    $0 ~ ("^[[:space:]]*[0-9]+[[:space:]]+([^[:space:]]*/)?python3[[:space:]]+(([^[:space:]]*/)?)" pat "([[:space:]]|$)") {
      print $1
    }
  '
}

# ── SECTION 1: Process Health (is exactly 1 of each running?) ──
echo ""; echo "--- Processes ---"
for proc in "host-ops-executor.py:Executor" "tap-daemon.py:Tap Bot" "telegram-listener.py:Telegram Listener" "backbone-listener.py:Backbone" "scribe-watcher.py:Scribe Watcher" "relay-handoff-watcher.py:Handoff Watcher"; do
  name="${proc#*:}"; pattern="${proc%%:*}"
  PIDS=$(python_worker_pids "$pattern")
  COUNT=$(printf "%s\n" "$PIDS" | sed '/^$/d' | wc -l)
  if [ "$COUNT" -eq 0 ]; then
    issue "$name is NOT running" "Crashed or killed" "Check systemd/cron guard. Restart: systemctl start openclaw-${name,,} or pgrep cron guard"
  elif [ "$COUNT" -gt 1 ]; then
    PIDS=$(printf "%s\n" "$PIDS" | paste -sd, -)
    issue "$name has $COUNT python processes (expected 1). PIDs: $PIDS" "Orphan from restart" "Kill all, restart: pkill -9 -f '$pattern'; restart via systemd"
  else
    echo "  $name: OK (1 instance)"
  fi
done

# Gateway (docker)
GW_STATUS=$(docker inspect --format '{{.State.Status}}' openclaw-openclaw-gateway-1 2>/dev/null || echo "missing")
if [ "$GW_STATUS" = "running" ]; then
  echo "  Gateway: OK (running)"
else
  issue "Gateway is $GW_STATUS" "OOM, config error, mount issue" "docker compose -f /root/openclaw/docker-compose.yml up -d openclaw-gateway"
fi

# Ollama
if curl -s --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1; then
  OLLAMA_MODELS=$(curl -s --max-time 3 http://localhost:11434/api/tags 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('models',[])))" 2>/dev/null || echo "?")
  echo "  Ollama: OK ($OLLAMA_MODELS models)"
else
  issue "Ollama is NOT responding" "Service down or port conflict" "systemctl restart ollama"
fi

# ── SECTION 1b: Systemd Service Health (dedup + boot guards) ──
echo ""; echo "--- Systemd Guards ---"
# Executor: exactly one service enabled
EXEC_ENABLED=$(systemctl is-enabled host-ops-executor.service 2>/dev/null)
OPS_ENABLED=$(systemctl is-enabled openclaw-host-ops.service 2>/dev/null)
if [ "$EXEC_ENABLED" = "enabled" ] && [ "$OPS_ENABLED" = "enabled" ]; then
  issue "Both executor services enabled (race on ops.db)" "host-ops-executor + openclaw-host-ops both enabled" "systemctl disable host-ops-executor.service"
elif [ "$OPS_ENABLED" != "enabled" ]; then
  issue "openclaw-host-ops.service not enabled" "Won't start on reboot" "systemctl enable openclaw-host-ops.service"
else
  echo "  Executor: OK (openclaw-host-ops only)"
fi

# Handoff watcher: exactly one service enabled
HW_OLD=$(systemctl is-enabled openclaw-handoff-watcher.service 2>/dev/null)
HW_NEW=$(systemctl is-enabled relay-handoff-watcher.service 2>/dev/null)
if [ "$HW_OLD" = "enabled" ] && [ "$HW_NEW" = "enabled" ]; then
  issue "Both handoff watcher services enabled (race on reboot)" "Duplicate systemd units" "systemctl disable openclaw-handoff-watcher.service"
else
  echo "  Handoff watcher: OK (no duplicates)"
fi

# Bridge boot
for svc in openclaw-bridge openclaw-bridge-corinne; do
  if [ "$(systemctl is-enabled ${svc}.service 2>/dev/null)" != "enabled" ]; then
    issue "${svc} not enabled at boot" "Won't survive reboot" "systemctl enable ${svc}.service"
  fi
done
BR_DEAD=$(ls /etc/systemd/system/multi-user.target.wants/openclaw-dashboard.service 2>/dev/null)
if [ -n "$BR_DEAD" ]; then
  issue "Dead symlink: openclaw-dashboard.service" "Points to missing unit file" "rm /etc/systemd/system/multi-user.target.wants/openclaw-dashboard.service"
else
  echo "  Bridge boot: OK (bridge + corinne enabled)"
fi

# ── SECTION 1c: Gateway Deep Health ──
echo ""; echo "--- Gateway Probes ---"
GW_HEALTH=$(oc health --json 2>&1 | tail -n +2)
if echo "$GW_HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d['ok'] else 1)" 2>/dev/null; then
  GW_AGENTS=$(echo "$GW_HEALTH" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('agents',[])))" 2>/dev/null || echo "?")
  echo "  Gateway health: OK ($GW_AGENTS agents)"
  if [ "${GW_AGENTS:-0}" -ne 18 ]; then
    issue "Gateway has $GW_AGENTS agents (expected 18)" "Agent config missing or failed to load" "Check openclaw.json, restart gateway"
  fi
  # Channel probes
  for ch in telegram discord; do
    CH_OK=$(echo "$GW_HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); print('ok' if d['channels']['$ch']['probe']['ok'] else 'fail')" 2>/dev/null || echo "fail")
    if [ "$CH_OK" = "ok" ]; then
      echo "  $ch: probe OK"
    else
      issue "$ch probe FAILED" "Bot token invalid or API unreachable" "Check channel config in openclaw.json"
    fi
  done
else
  issue "Gateway health check FAILED" "Gateway not responding or JSON parse error" "docker compose restart openclaw-gateway"
fi

# ── SECTION 2: Task Pipeline (are tasks flowing?) ──
echo ""; echo "--- Task Pipeline ---"
PENDING=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='pending'" 2>/dev/null || echo 0)
IN_PROGRESS=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='in_progress'" 2>/dev/null || echo 0)
BLOCKED=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='blocked'" 2>/dev/null || echo 0)
echo "  Pending: $PENDING | In progress: $IN_PROGRESS | Blocked: $BLOCKED"

# Last completed task
LAST_COMPLETED=$(sqlite3 "$OPS_DB" "SELECT id || ' (' || agent || ') at ' || COALESCE(completed_at, updated_at) FROM tasks WHERE status='completed' ORDER BY id DESC LIMIT 1" 2>/dev/null)
echo "  Last completed: ${LAST_COMPLETED:-none}"

# Stuck pending (quarantined)
if [ "${PENDING:-0}" -gt 0 ]; then
  Q_PENDING=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks t WHERE t.status='pending' AND EXISTS (SELECT 1 FROM kv WHERE key='agent_quarantine_' || t.agent AND value='true')" 2>/dev/null || echo 0)
  if [ "${Q_PENDING:-0}" -gt 0 ]; then
    issue "$Q_PENDING pending task(s) assigned to quarantined agents" "Nightly dispatch or auto-heal routed to quarantined agents" "Executor will auto-cancel these on next poll. If stuck, cancel manually."
  fi
  # Stuck by dead blocked_by
  DEAD_DEP=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks t WHERE t.status='pending' AND t.blocked_by IS NOT NULL AND t.blocked_by IN (SELECT CAST(id AS TEXT) FROM tasks WHERE status IN ('cancelled','failed'))" 2>/dev/null || echo 0)
  if [ "${DEAD_DEP:-0}" -gt 0 ]; then
    issue "$DEAD_DEP pending task(s) blocked by cancelled/failed tasks" "blocked_by points to dead tasks" "UPDATE tasks SET blocked_by=NULL WHERE status='pending' AND blocked_by IN (SELECT CAST(id AS TEXT) FROM tasks WHERE status IN ('cancelled','failed'))"
  fi
fi

# Stuck in_progress
if [ "${IN_PROGRESS:-0}" -gt 0 ]; then
  STUCK=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='in_progress' AND updated_at < datetime('now', '-15 minutes')" 2>/dev/null || echo 0)
  if [ "${STUCK:-0}" -gt 0 ]; then
    STUCK_IDS=$(sqlite3 "$OPS_DB" "SELECT id FROM tasks WHERE status='in_progress' AND updated_at < datetime('now', '-15 minutes')" 2>/dev/null)
    issue "$STUCK task(s) stuck in_progress >15 min (IDs: $STUCK_IDS)" "Executor was killed mid-task" "Reset to pending: UPDATE tasks SET status='pending' WHERE id IN ($STUCK_IDS)"
  fi
fi

# ── SECTION 3: Configuration Truth (what's ACTUALLY configured right now?) ──
echo ""; echo "--- Configuration (live reads) ---"
MODEL=$(python3 -c "import json; print(json.load(open('$OPENCLAW_JSON')).get('agents',{}).get('defaults',{}).get('model',{}).get('primary','?'))" 2>/dev/null || echo "?")
echo "  Default model: $MODEL"

# Model routing breakdown
python3 -c "
import json
cfg=json.load(open('$OPENCLAW_JSON'))
cdx=mst=oth=0
for a in cfg['agents']['list']:
    m=a.get('model',{})
    p=m.get('primary','?') if isinstance(m,dict) else m
    if 'codex' in p: cdx+=1
    elif 'mistral' in p: mst+=1
    else: oth+=1
print(f'  Routing: {cdx} Codex / {mst} Mistral / {oth} other (total {cdx+mst+oth})')
" 2>/dev/null || echo "  Routing: parse error"

QUARANTINED=$(sqlite3 "$OPS_DB" "SELECT GROUP_CONCAT(REPLACE(key,'agent_quarantine_','')) FROM kv WHERE key LIKE 'agent_quarantine_%' AND value='true'" 2>/dev/null)
echo "  Quarantined: ${QUARANTINED:-none}"

AGENT_COUNT=$(sqlite3 "$OPS_DB" "SELECT COUNT(DISTINCT agent) FROM tasks WHERE status IN ('pending','in_progress')" 2>/dev/null || echo 0)
echo "  Active agents (with pending/in_progress): $AGENT_COUNT"

# ── SECTION 4: Engine Health (can models respond?) ──
echo ""; echo "--- Engine Health ---"
CODEX_RECENT=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM engine_usage WHERE engine='codex' AND ts > datetime('now', '-4 hours')" 2>/dev/null || echo 0)
CODEX_OK=$(sqlite3 "$OPS_DB" "SELECT SUM(success) FROM engine_usage WHERE engine='codex' AND ts > datetime('now', '-4 hours')" 2>/dev/null || echo 0)
echo "  Codex (4h): ${CODEX_OK:-0}/${CODEX_RECENT:-0} success"
if [ "${CODEX_RECENT:-0}" -gt 3 ] && [ "${CODEX_OK:-0}" -eq 0 ]; then
  issue "Codex failing: 0/${CODEX_RECENT} in 4h" "OAuth expired or rate limited" "codex login status. If expired: create codex-reauth task"
fi

# ── SECTION 5: Cron Health (are scheduled jobs running?) ──
echo ""; echo "--- Cron Health ---"
for cron_name in stability-monitor truth-gate agent-babysitter; do
  LOG="/root/.openclaw/logs/${cron_name}.log"
  if [ -f "$LOG" ] && [ -s "$LOG" ]; then
    LAST_TS=$(tail -1 "$LOG" | grep -oP '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}' || echo "?")
    echo "  $cron_name: last=$LAST_TS"
  else
    warn "$cron_name has no log output"
  fi
done

# ── SECTION 6: Bridge Health ──
echo ""; echo "--- Bridge ---"
for br_entry in "8082:Prod:openclaw-bridge" "8083:Dev:openclaw-bridge-dev" "8084:Corinne:openclaw-bridge-corinne"; do
  BR_PORT="${br_entry%%:*}"; br_rest="${br_entry#*:}"; BR_NAME="${br_rest%%:*}"; BR_SVC="${br_rest#*:}"
  BR_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:${BR_PORT}/api/health" 2>/dev/null || echo "000")
  if [ "$BR_CODE" = "200" ]; then
    echo "  $BR_NAME (:${BR_PORT}): OK"
  else
    issue "Bridge $BR_NAME not responding (HTTP $BR_CODE on :${BR_PORT})" "Crash or port conflict" "systemctl restart $BR_SVC"
  fi
done

# Dev/prod sync
SYNC_ISSUES=0
for f in index.html style.css app.js dashboard-api.py; do
  DEV_H=$(md5sum "/root/bridge-dev/$f" 2>/dev/null | cut -d' ' -f1)
  PROD_H=$(md5sum "/root/bridge/$f" 2>/dev/null | cut -d' ' -f1)
  if [ "$DEV_H" != "$PROD_H" ]; then
    SYNC_ISSUES=$((SYNC_ISSUES + 1))
  fi
done
if [ "$SYNC_ISSUES" -gt 0 ]; then
  warn "Bridge dev/prod out of sync ($SYNC_ISSUES file(s)). Run: bash /root/.openclaw/scripts/bridge-promote.sh"
fi

# ── SECTION 7: Resources ──
echo ""; echo "--- Resources ---"
DISK_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
MEM_AVAIL=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
echo "  Disk: ${DISK_PCT}% | RAM: ${MEM_AVAIL}MB free"
if [ "${DISK_PCT:-0}" -gt 85 ]; then issue "Disk ${DISK_PCT}%" "Log growth or build artifacts" "logrotate -f /etc/logrotate.d/openclaw"; fi
if [ "${MEM_AVAIL:-9999}" -lt 500 ]; then issue "RAM critical: ${MEM_AVAIL}MB" "Too many processes or gateway OOM" "Check: ps aux --sort=-%mem | head -10"; fi

# ── SECTION 8: Data Integrity ──
echo ""; echo "--- Data Integrity ---"
# ops.db writable?
sqlite3 "$OPS_DB" "INSERT INTO kv (key,value,updated_at) VALUES ('_probe','1',datetime('now')) ON CONFLICT(key) DO UPDATE SET value='1'" 2>/dev/null && echo "  ops.db: WRITABLE" || issue "ops.db NOT writable" "Database locked by another process" "fuser $OPS_DB — find and fix the locking process"
sqlite3 "$OPS_DB" "DELETE FROM kv WHERE key='_probe'" 2>/dev/null

# ideas-registry readable?
python3 -c "import json; json.load(open('/root/.openclaw/workspace-spec-projects/ideas-registry.json'))" 2>/dev/null && echo "  ideas-registry: READABLE" || issue "ideas-registry.json unreadable" "JSON parse error or missing file" "Check: python3 -c 'import json; json.load(open(...))'"

# ── SUMMARY ──
echo ""
echo "=== SUMMARY: $ISSUES issue(s), $WARNINGS warning(s) ==="
if [ "$ISSUES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "System is healthy. All checks passed."
fi
