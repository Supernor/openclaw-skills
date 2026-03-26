#!/usr/bin/env bash
# hardcode-checker.sh — Scan cron scripts for hardcoded data that should be dynamic
# Run weekly or on-demand. Charts findings for Captain to address.
set -eo pipefail

SCRIPTS_DIR="/root/.openclaw/scripts"
WORKSPACE_BASE="/root/.openclaw"
LOG="/root/.openclaw/logs/hardcode-checker.log"
FINDINGS=()

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOG"; }
log "Hardcode checker starting"

# 1. Dynamic agent list (source of truth)
LIVE_AGENTS=$(docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway cat /home/node/.openclaw/openclaw.json 2>/dev/null | python3 -c "import sys,json; print(' '.join(a['id'] for a in json.load(sys.stdin).get('agents',{}).get('list',[])))" 2>/dev/null || echo "")
LIVE_COUNT=$(echo "$LIVE_AGENTS" | wc -w)
log "Live agents ($LIVE_COUNT): $LIVE_AGENTS"

# 2. Scan scripts for hardcoded agent arrays
for f in "$SCRIPTS_DIR"/*.sh "$SCRIPTS_DIR"/*.py; do
  [ -f "$f" ] || continue
  base=$(basename "$f")

  # Check for hardcoded AGENTS= arrays (bash)
  hardcoded=$(grep -n 'AGENTS=(' "$f" 2>/dev/null | grep -v "Dynamic\|dynamic\|openclaw.json\|fallback" || true)
  if [ -n "$hardcoded" ]; then
    FINDINGS+=("HARDCODED_AGENTS|$base|$hardcoded")
    log "  FOUND hardcoded AGENTS in $base: $hardcoded"
  fi

  # Check for old tool names
  old_tools=$(grep -n "memory_store\|memory_recall\|gemini-3-pro[^-]" "$f" 2>/dev/null || true)
  if [ -n "$old_tools" ]; then
    FINDINGS+=("STALE_TOOL_NAME|$base|$old_tools")
    log "  FOUND stale tool name in $base"
  fi
done

# 3. Scan workspace TOOLS.md for old tool names
for ws in "$WORKSPACE_BASE"/workspace*/TOOLS.md; do
  [ -f "$ws" ] || continue
  base=$(echo "$ws" | sed "s|$WORKSPACE_BASE/||")
  old_refs=$(grep -n "memory_store\|memory_recall\|gemini-3-pro[^-]" "$ws" 2>/dev/null || true)
  if [ -n "$old_refs" ]; then
    FINDINGS+=("STALE_WORKSPACE_REF|$base|$old_refs")
    log "  FOUND stale reference in $base"
  fi
done

# 4. Check agent coverage in session-maintenance
SM_AGENTS=$(grep -oP "(?<=AGENTS_JSON=).*" "$SCRIPTS_DIR/session-maintenance.sh" 2>/dev/null | head -1 || echo "dynamic")
if echo "$SM_AGENTS" | grep -q "relay.*main.*spec"; then
  # Has fallback list — check if it covers all live agents
  for agent in $LIVE_AGENTS; do
    if ! echo "$SM_AGENTS" | grep -q "$agent"; then
      FINDINGS+=("MISSING_AGENT|session-maintenance.sh|Agent $agent not in fallback list")
      log "  MISSING $agent from session-maintenance fallback"
    fi
  done
fi

# 5. Summary
TOTAL=${#FINDINGS[@]}
log "Scan complete: $TOTAL findings"

if [ "$TOTAL" -gt 0 ]; then
  SUMMARY="Hardcode checker $(date +%Y-%m-%d): $TOTAL findings."
  for f in "${FINDINGS[@]}"; do
    IFS='|' read -r type file detail <<< "$f"
    SUMMARY="$SUMMARY $type in $file."
  done

  # Chart it (if chart tool available)
  bash "$SCRIPTS_DIR/chart-handler.sh" add \
    "hardcode-check-$(date +%Y-%m-%d)" \
    "$SUMMARY Intent: coherent. Discovered: $(date +%Y-%m-%d)." \
    issue 0.7 2>/dev/null || log "Chart write failed (non-blocking)"

  log "Charted $TOTAL findings"
else
  log "All clean — no hardcoded data found"
fi
