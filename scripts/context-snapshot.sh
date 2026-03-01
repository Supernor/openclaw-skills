#!/usr/bin/env bash
# context-snapshot.sh — Generate a pre-flight context snapshot for coding-agent handoff
# Writes current system state to ~/.openclaw/coding-agent/context/current.json
# Agents call this before escalating to Claude Code — gives full situational awareness
# with zero token cost on either side.
#
# Usage: context-snapshot.sh

set -eo pipefail

BASE="/home/node/.openclaw"
OUTDIR="${BASE}/coding-agent/context"
OUTFILE="${OUTDIR}/current.json"
mkdir -p "$OUTDIR"

# Model health
MODEL_HEALTH="null"
if [ -f "${BASE}/model-health.json" ]; then
  MODEL_HEALTH=$(jq -c '.' "${BASE}/model-health.json" 2>/dev/null || echo "null")
fi

# Key drift
KEY_DRIFT="null"
if [ -x "${BASE}/scripts/key-drift-check.sh" ]; then
  KEY_DRIFT=$("${BASE}/scripts/key-drift-check.sh" 2>/dev/null || echo '{"status":"ERROR","error":"script failed"}')
fi

# Repo health
REPO_HEALTH="null"
if [ -x "${BASE}/scripts/repo-health.sh" ]; then
  REPO_HEALTH=$("${BASE}/scripts/repo-health.sh" 2>/dev/null || echo '{"status":"ERROR","error":"script failed"}')
fi

# Recent gateway errors (last 5)
RECENT_ERRORS="[]"
if [ -x "${BASE}/scripts/gateway-log-query.sh" ]; then
  RAW_ERRORS=$("${BASE}/scripts/gateway-log-query.sh" --errors --limit 5 2>/dev/null || echo "")
  if [ -n "$RAW_ERRORS" ]; then
    RECENT_ERRORS=$(echo "$RAW_ERRORS" | head -5 | jq -sc '.' 2>/dev/null || echo "[]")
  fi
fi

# Cron status
CRON_STATUS="null"
if [ -f "${BASE}/cron/jobs.json" ]; then
  CRON_STATUS=$(jq -c '[.jobs[] | {name: .name, enabled: .enabled, lastStatus: .state.lastStatus, lastRunAt: (.state.lastRunAtMs // 0 | . / 1000 | strftime("%Y-%m-%dT%H:%M:%SZ")), nextRunAt: (.state.nextRunAtMs // 0 | . / 1000 | strftime("%Y-%m-%dT%H:%M:%SZ"))}]' "${BASE}/cron/jobs.json" 2>/dev/null || echo "null")
fi

# Recent notifications (last 5)
RECENT_NOTIFS="[]"
if [ -f "${BASE}/model-health-notifications.jsonl" ]; then
  RECENT_NOTIFS=$(tail -5 "${BASE}/model-health-notifications.jsonl" 2>/dev/null | jq -sc '.' 2>/dev/null || echo "[]")
fi

# Disk summary
DISK=$(du -sm "${BASE}" 2>/dev/null | awk '{print $1}')

# Active incidents
INCIDENTS="[]"
if [ -x "${BASE}/scripts/incident-manager.sh" ]; then
  RAW_INCIDENTS=$("${BASE}/scripts/incident-manager.sh" list 2>/dev/null || echo "[]")
  INCIDENTS=$(echo "$RAW_INCIDENTS" | jq -c 'if type == "array" then . elif .issues then .issues else [] end' 2>/dev/null || echo "[]")
fi

# Registry version
REG_VERSION="null"
if [ -f "${BASE}/registry.json" ]; then
  REG_VERSION=$(jq -c '.version' "${BASE}/registry.json" 2>/dev/null || echo "null")
fi

# Build snapshot
jq -n \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson modelHealth "$MODEL_HEALTH" \
  --argjson keyDrift "$KEY_DRIFT" \
  --argjson repoHealth "$REPO_HEALTH" \
  --argjson recentErrors "$RECENT_ERRORS" \
  --argjson cronStatus "$CRON_STATUS" \
  --argjson recentNotifs "$RECENT_NOTIFS" \
  --argjson incidents "$INCIDENTS" \
  --argjson regVersion "$REG_VERSION" \
  --arg diskMB "$DISK" \
  '{
    timestamp: $ts,
    modelHealth: $modelHealth,
    keyDrift: $keyDrift,
    repoHealth: $repoHealth,
    recentErrors: $recentErrors,
    cronStatus: $cronStatus,
    recentNotifications: $recentNotifs,
    activeIncidents: $incidents,
    registryVersion: $regVersion,
    diskUsageMB: ($diskMB | tonumber)
  }' > "$OUTFILE"

echo "{\"status\":\"ok\",\"path\":\"${OUTFILE}\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
