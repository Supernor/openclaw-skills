#!/usr/bin/env bash
# sitrep-cron.sh — Generate sitrep from CLI data (no agent call, zero token cost)
# Intent: Efficient [I06]
# Converted from agent-based to bash-template: 2026-03-10 (saves ~$8.70/mo)
set -uo pipefail

COMPOSE="docker compose -f /root/openclaw/docker-compose.yml"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DATE_SHORT=$(date -u +"%Y-%m-%d %H:%M UTC")
SITREP_FILE="/tmp/sitrep-staging.md"

# --- Gather data (all bash/CLI, zero API cost) ---

# Check if gateway is running first (determines fallback paths)
GATEWAY_RUNNING=$(docker inspect --format '{{.State.Status}}' openclaw-openclaw-gateway-1 2>/dev/null || echo "missing")

# Health check (with gateway-down fallback)
if [ "$GATEWAY_RUNNING" = "running" ]; then
  HEALTH=$($COMPOSE exec -T openclaw-gateway openclaw health 2>&1 | grep -v "level=warning" | head -3) || HEALTH="Gateway health check failed"
  TELEGRAM=$(echo "$HEALTH" | grep -oP 'Telegram: \K\S+' || echo "unknown")
  DISCORD=$(echo "$HEALTH" | grep -oP 'Discord: \K\S+' || echo "unknown")
  RECENT_ERRORS=$($COMPOSE logs --since=4h openclaw-gateway 2>&1 | grep -c "isError=true" || true)
else
  # Fallback: read from stability-state.json
  HEALTH="Gateway DOWN ($GATEWAY_RUNNING)"
  TELEGRAM=$(python3 -c "import json; print(json.load(open('/root/.openclaw/stability-state.json')).get('telegram','unknown'))" 2>/dev/null || echo "unknown")
  DISCORD=$(python3 -c "import json; print(json.load(open('/root/.openclaw/stability-state.json')).get('discord','unknown'))" 2>/dev/null || echo "unknown")
  RECENT_ERRORS="N/A (gateway down)"
fi
RECENT_ERRORS=${RECENT_ERRORS:-0}

# Chart count
CHART_COUNT=$(chart count 2>/dev/null | grep -oP '\d+' || echo "?")

# Chart issues
ISSUE_COUNT=$(chart search "issue" 2>/dev/null | grep -c "issue" || true)
ISSUE_COUNT=${ISSUE_COUNT:-0}

# Helm usage stats
HELM_STATS=$(python3 -c "
import json
from collections import Counter
lines = open('/root/.openclaw/helm-usage.log').readlines()
engines = Counter()
failovers = 0
for line in lines:
    try:
        d = json.loads(line)
        key = d.get('agent','?') + '/' + d.get('engine','?')
        engines[key] += 1
        if d.get('attempts',1) > 1:
            failovers += 1
    except: pass
total = len(lines)
rate = f'{failovers/total*100:.1f}' if total else '0'
print(f'{total}|{failovers}|{rate}')
top = '; '.join(f'{k} ({v})' for k,v in engines.most_common(5))
print(top)
" 2>/dev/null)
HELM_TOTAL=$(echo "$HELM_STATS" | head -1 | cut -d'|' -f1)
HELM_FAILOVERS=$(echo "$HELM_STATS" | head -1 | cut -d'|' -f2)
HELM_RATE=$(echo "$HELM_STATS" | head -1 | cut -d'|' -f3)
HELM_TOP=$(echo "$HELM_STATS" | tail -1)

# Ideas pipeline
IDEAS=$(sqlite3 /root/.openclaw/ops.db "SELECT status || ':' || COUNT(*) FROM intents GROUP BY status" 2>/dev/null | tr '\n' ' ' || echo "unavailable")

# Satisfaction
SAT_SUMMARY=$(/root/.openclaw/scripts/satisfaction-summary.sh 2>/dev/null || echo "Satisfaction: unavailable")

# Cron health (quick check)
CRON_FAILS=$(cron-health 2>/dev/null | grep -c "FAIL\|ERROR" || true)
CRON_FAILS=${CRON_FAILS:-0}

# Phase 5: Scope gate status
SCOPE_TOTAL=$(sqlite3 /root/.openclaw/scope.db "SELECT COUNT(*) FROM scope" 2>/dev/null || echo "0")
SCOPE_SYSTEM=$(sqlite3 /root/.openclaw/scope.db "SELECT COUNT(*) FROM scope WHERE scope_tier='system'" 2>/dev/null || echo "0")
SCOPE_MODE=${SCOPE_GATE_MODE:-shadow}
SCOPE_GATE_LOG_24H=$(sqlite3 /root/.openclaw/scope.db "SELECT COUNT(*) FROM gate_log WHERE ts > strftime('%Y-%m-%dT%H:%M:%SZ','now', '-24 hours')" 2>/dev/null || echo "0")

# KnownSelf registry freshness (mem:drift) — the freshness loop's scheduled
# beat (A1b). Running mem-drift-check.py (NOT --dry) UPSERTS the mem:drift row
# into signal_status, which the Bridge host-signals grid / MOTD / nightly
# digest already read; we also capture it for the sitrep section below. It is
# READ-ONLY on mem_* (its only write is that one signal row) and exits 0 even
# when drift exists (only the signal carries state), so `set -uo pipefail`
# will not abort the sitrep run on drift. No new cron — this rides the
# existing 4h sitrep beat.
MEM_DRIFT=$(python3 /root/.openclaw/scripts/mem-drift-check.py --json 2>/dev/null | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d['status'].upper()+'/'+d['severity']+' | '+d['value'])
    print(d['message'])
except Exception:
    print('unavailable')
    print('mem-drift-check produced no report (registry unseeded or ops.db unreadable)')
" 2>/dev/null) || MEM_DRIFT=$'unavailable\nmem-drift-check failed to run'
MEM_DRIFT_STATUS=$(printf '%s\n' "$MEM_DRIFT" | head -1)
MEM_DRIFT_MSG=$(printf '%s\n' "$MEM_DRIFT" | tail -1)

# --- Build sitrep ---

cat > "$SITREP_FILE" << EOF
# SITREP — ${DATE_SHORT}

## System Health
- Gateway: OK | Telegram: ${TELEGRAM} | Discord: ${DISCORD}
- Errors (last 4h): ${RECENT_ERRORS}
- Cron failures: ${CRON_FAILS}

## Chartroom
- Total charts: ${CHART_COUNT}
- Open issues: ${ISSUE_COUNT}

## Helm Routing
- Total calls: ${HELM_TOTAL} | Failovers: ${HELM_FAILOVERS} (${HELM_RATE}%)
- Top: ${HELM_TOP}

## Ideas Pipeline
- ${IDEAS}

${SAT_SUMMARY}

## Context Boundaries (Phase 5)
- Scope entries: ${SCOPE_TOTAL} | System: ${SCOPE_SYSTEM} | Mode: ${SCOPE_MODE}
- Gate log (24h): ${SCOPE_GATE_LOG_24H} evaluations

## KnownSelf Freshness (mem:drift)
- ${MEM_DRIFT_STATUS}
- ${MEM_DRIFT_MSG}

---
Generated: ${NOW} (bash, zero token cost)
EOF

# Always save to host (survives gateway restarts)
cp "$SITREP_FILE" /root/.openclaw/sitrep.md

# Copy into container if running
if [ "$GATEWAY_RUNNING" = "running" ]; then
  docker cp "$SITREP_FILE" "$($COMPOSE ps -q openclaw-gateway)":/home/node/.openclaw/sitrep.md 2>/dev/null || true
fi
rm -f "$SITREP_FILE"

echo "${NOW} sitrep generated (bash, gateway: $GATEWAY_RUNNING)"
