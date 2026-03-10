#!/bin/bash
# Staggered Agent Memory Init — runs after gateway startup
# Triggers QMD memory update for each agent with 1.5s delays
# Priority order: human-facing first, then core, then specialists
#
# Called by: post-restart hook or cron (1 min after boot)
# Replaces: onBoot: true (which fired all 16 simultaneously)

set -euo pipefail

LOG="/root/.openclaw/logs/staggered-init.log"
DELAY=1.5

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> "$LOG"; }

# Priority order: human-facing → core routing → specialists
AGENTS=(
  # Tier 1: Human-facing (must be ready first)
  "relay"
  "eoin"
  # Tier 2: Core routing
  "main"
  # Tier 3: Frequently called specialists
  "spec-strategy"
  "spec-ops"
  "spec-comms"
  "spec-research"
  # Tier 4: On-demand specialists
  "spec-dev"
  "spec-projects"
  "spec-security"
  "spec-design"
  "spec-systems"
  "spec-github"
  "spec-reactor"
  "spec-quartermaster"
  "spec-historian"
  "spec-realist"
  "spec-browser"
)

log "Starting staggered memory init (${#AGENTS[@]} agents, ${DELAY}s delay)"

CONTAINER_STATUS=$(docker inspect --format '{{.State.Status}}' openclaw-openclaw-gateway-1 2>/dev/null || echo "missing")
if [ "$CONTAINER_STATUS" != "running" ]; then
  log "ERROR: Gateway not running ($CONTAINER_STATUS), aborting"
  exit 1
fi

SUCCESS=0
FAIL=0

for AGENT in "${AGENTS[@]}"; do
  # Trigger a lightweight agent call to warm up the session/memory
  RESULT=$(docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway \
    openclaw agent --agent "$AGENT" -m "." --json 2>/dev/null | tail -1)

  if echo "$RESULT" | grep -q '"status":"ok"' 2>/dev/null; then
    log "OK: $AGENT initialized"
    SUCCESS=$((SUCCESS + 1))
  else
    log "WARN: $AGENT init may have failed"
    FAIL=$((FAIL + 1))
  fi

  sleep "$DELAY"
done

log "Staggered init complete: $SUCCESS ok, $FAIL warnings"
