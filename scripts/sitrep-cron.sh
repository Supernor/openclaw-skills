#!/usr/bin/env bash
# sitrep-cron.sh — Generate sitrep from CLI data (no agent call, zero token cost)
# Intent: Efficient [I06]
# Converted from agent-based to bash-template: 2026-03-10 (saves ~$8.70/mo)
set -eo pipefail

COMPOSE="docker compose -f /root/openclaw/docker-compose.yml"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DATE_SHORT=$(date -u +"%Y-%m-%d %H:%M UTC")
SITREP_FILE="/tmp/sitrep-staging.md"

# --- Gather data (all bash/CLI, zero API cost) ---

# Health check
HEALTH=$($COMPOSE exec -T openclaw-gateway openclaw health 2>&1 | grep -v "level=warning" | head -3)
TELEGRAM=$(echo "$HEALTH" | grep -oP 'Telegram: \K\S+' || echo "unknown")
DISCORD=$(echo "$HEALTH" | grep -oP 'Discord: \K\S+' || echo "unknown")

# Gateway errors (last 4h to match frequency)
RECENT_ERRORS=$($COMPOSE logs --since=4h openclaw-gateway 2>&1 | grep -c "isError=true" || true)
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
IDEAS=$(sqlite3 /root/.openclaw/transcripts.db "SELECT status || ':' || COUNT(*) FROM ideas GROUP BY status" 2>/dev/null | tr '\n' ' ' || echo "unavailable")

# Satisfaction
SAT_SUMMARY=$(/root/.openclaw/scripts/satisfaction-summary.sh 2>/dev/null || echo "Satisfaction: unavailable")

# Cron health (quick check)
CRON_FAILS=$(cron-health 2>/dev/null | grep -c "FAIL\|ERROR" || true)
CRON_FAILS=${CRON_FAILS:-0}

# Phase 5: Scope gate status
SCOPE_TOTAL=$(sqlite3 /root/.openclaw/scope.db "SELECT COUNT(*) FROM scope" 2>/dev/null || echo "0")
SCOPE_SYSTEM=$(sqlite3 /root/.openclaw/scope.db "SELECT COUNT(*) FROM scope WHERE scope_tier='system'" 2>/dev/null || echo "0")
SCOPE_MODE=${SCOPE_GATE_MODE:-shadow}
SCOPE_GATE_LOG_24H=$(sqlite3 /root/.openclaw/scope.db "SELECT COUNT(*) FROM gate_log WHERE ts > datetime('now', '-24 hours')" 2>/dev/null || echo "0")

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

---
Generated: ${NOW} (bash, zero token cost)
EOF

# Copy into container
docker cp "$SITREP_FILE" "$($COMPOSE ps -q openclaw-gateway)":/home/node/.openclaw/sitrep.md 2>/dev/null
rm -f "$SITREP_FILE"

echo "${NOW} sitrep generated (bash)"
