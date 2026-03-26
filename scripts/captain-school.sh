#!/usr/bin/env bash
# captain-school.sh — Captain's nightly agent update session
# Runs at 1:30am UTC. Reads system state, updates agent workspaces with current context.
# This ensures agents don't work with stale information about tools, patterns, or architecture.

set -eo pipefail
LOG="/root/.openclaw/logs/captain-school.log"
WORKSPACE_BASE="/root/.openclaw"
COMPOSE_DIR="/root/openclaw"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >> "$LOG"; }
log "Captain school session starting"

# Skip if system is stressed
LOAD=$(cat /proc/loadavg | awk '{print $1}')
if (( $(echo "$LOAD > 3.0" | bc -l 2>/dev/null || echo 0) )); then
  log "Load too high ($LOAD), skipping"
  exit 0
fi

# --- Gather current system state (DYNAMIC — reads from live sources) ---

# MCP tools: read from the shared reference file (single source of truth)
MCP_TOOLS_REF="$WORKSPACE_BASE/docs/mcp-tools-reference.md"
if [ -f "$MCP_TOOLS_REF" ]; then
  MCP_TOOLS=$(grep "^- \`" "$MCP_TOOLS_REF" | sed 's/^- //' | head -30 | tr '\n' '; ')
else
  MCP_TOOLS="(reference file missing — run: capabilities MCP tool for full list)"
fi

# Bridge status: query live
BRIDGE_PROD=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8082/api/health 2>/dev/null || echo "down")
BRIDGE_DEV=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8083/api/health 2>/dev/null || echo "down")
BRIDGE_INFO="Bridge prod: http://localhost:8082 (status: $BRIDGE_PROD) | Bridge dev: http://localhost:8083 (status: $BRIDGE_DEV)
Dev/prod workflow: all edits go to dev, Deploy button promotes.
Full reference: docs/mcp-tools-reference.md — agents should call capabilities MCP tool to self-discover."

# Current engine info
ENGINE_INFO=$(sqlite3 /root/.openclaw/ops.db "
SELECT engine || COALESCE(' ' || pool, '') || ': ' ||
  COALESCE(CAST(capacity AS TEXT) || '/week', 'unlimited') ||
  ' (' || (SELECT COUNT(*) FROM engine_usage u WHERE u.engine=e.engine AND (u.pool IS e.pool OR (u.pool IS NULL AND e.pool IS NULL)) AND u.ts > datetime('now', '-7 days')) || ' used this week)'
FROM engine_fuel e ORDER BY engine" 2>/dev/null | tr '\n' '; ')

# Recent completed tasks (what the system learned)
RECENT=$(sqlite3 /root/.openclaw/ops.db "
SELECT '#' || id || ' ' || agent || ': ' || substr(task,1,60)
FROM tasks WHERE status='completed' AND updated_at > datetime('now', '-24 hours')
ORDER BY id DESC LIMIT 10" 2>/dev/null | tr '\n' '; ')

# Current architecture facts
ARCH_FACTS="Task execution: host-ops-executor (systemd, 30s poll) for host_op tasks. task-runner (cron 15m) for generic tasks.
Concurrency cap: 2 system-wide. Circuit breaker: 3 failures/hour.
Self-decomposition: failed tasks output JSON subtasks.
Agents access system state via Bridge API (browser tool) at localhost:8082."

# --- Build the school briefing ---
BRIEFING="# System Update — $(date +%Y-%m-%d)

## Tools Available
$MCP_TOOLS

## Bridge (Command Center)
$BRIDGE_INFO

## Engines
$ENGINE_INFO

## Recent Work (last 24h)
$RECENT

## Architecture
$ARCH_FACTS

## Rules
- Check /api/tasks before starting work that might overlap
- Check /api/bridge-state before restarting any service
- Use subagents or sessions_send to collaborate, not direct file edits
- Every interactive UI element uses Tactyl state machines (data-state)
- All Bridge edits go to dev (:8083), never prod directly"

# --- Update each agent's workspace ---
# Dynamic: scan for all workspace directories (never hardcode — agents change)
AGENTS=()
for d in "$WORKSPACE_BASE"/workspace "$WORKSPACE_BASE"/workspace-*/; do
  [ -d "$d" ] && AGENTS+=("$(basename "$d")")
done

UPDATED=0
# Human-facing agents (relay, eoin) have hand-tuned HEARTBEAT.md — don't overwrite.
# Their heartbeats point to /api/digest and capabilities() instead of static dumps.
SKIP_HEARTBEAT="workspace-relay workspace-eoin"
for ws in "${AGENTS[@]}"; do
  WS_PATH="$WORKSPACE_BASE/$ws"
  if [ -d "$WS_PATH" ]; then
    if echo "$SKIP_HEARTBEAT" | grep -q "$ws"; then
      log "Skipping HEARTBEAT.md for $ws (hand-tuned, dynamic)"
    else
      echo "$BRIEFING" > "$WS_PATH/HEARTBEAT.md"
    fi
    UPDATED=$((UPDATED + 1))
  fi
done

log "Updated $UPDATED agent workspaces with current system state"

# --- Chart the school session ---
chart add "school-$(date +%Y-%m-%d)" "Captain school session $(date +%Y-%m-%d). Updated $UPDATED agent workspaces. Engines: $ENGINE_INFO. Recent: $RECENT. Intent: coherent. Discovered: $(date +%Y-%m-%d)." reading 0.6 2>/dev/null || true

log "Captain school session complete"

# --- Phase 2: Captain reviews and cleans agent workspaces ---
# Dispatch to Captain via gateway — Captain reads the current state,
# reviews each agent's TOOLS.md and SOUL.md, and cleans up stale information.

log "Phase 2: Dispatching Captain for workspace review"

# Only if load allows
LOAD2=$(cat /proc/loadavg | awk '{print $1}')
if (( $(echo "$LOAD2 > 2.5" | bc -l 2>/dev/null || echo 0) )); then
  log "Load too high for Phase 2 ($LOAD2), skipping Captain dispatch"
  exit 0
fi

# Create a task for the host-ops-executor to dispatch Captain
sqlite3 /root/.openclaw/ops.db "INSERT INTO tasks (agent, urgency, status, task, context, meta) VALUES (
  'main', 'routine', 'pending',
  'Captain school: run tool-audit skill + review agent workspaces',
  'Nightly school session. Step 1: Run your tool-audit skill (skills/tool-audit/SKILL.md) to verify all agents know their MCP tools. Step 2: Review TOOLS.md and SOUL.md for active agents. Step 3: Call capabilities to get the LIVE tool list — never hardcode tool names. Step 4: For any agent missing tools, add pointer to docs/mcp-tools-reference.md and key tool names. Step 5: Chart results as tool-audit-YYYY-MM-DD. Focus on agents with recent activity (use ops_query). Keep changes minimal.',
  '{\"host_op\": \"reactor-dispatch\", \"agent\": \"main\", \"prompt\": \"You are Captain. This is your nightly school session. Review the workspace files for Relay, Dev, Ops Officer, and Scribe. Use chart_search_compact to find what changed today. Use browser tool to GET http://localhost:8082/api/tasks to see recent completed tasks. Update each agents TOOLS.md with current system capabilities. Remove stale references. Add missing tools. Keep it concise.\", \"telegram_chat_id\": \"8561305605\"}'
);"

log "Phase 2 task queued — Captain will review workspaces when executor picks it up"

# --- Phase 3: Realist reviews Captain's changes ---
log "Phase 3: Dispatching Realist to audit Captain's school session"

sqlite3 /root/.openclaw/ops.db "INSERT INTO tasks (agent, urgency, status, task, context, meta) VALUES (
  'spec-realist', 'routine', 'pending',
  'Realist audit: review Captain school session changes',
  'Captain just updated agent workspace files during the nightly school session.
Your job: verify the changes are accurate, not hallucinated, and actually help.
Check: 1) Are the tools listed in TOOLS.md actually available? Test with browser GET http://localhost:8082/api/health
2) Are the architecture claims in HEARTBEAT.md correct? Cross-reference with chart_search.
3) Did Captain miss any agents that need updates?
4) Is Captains own SOUL.md or workspace stale?
If you find issues, chart them as issue-school-YYYY-MM-DD and create a fix task via ops_insert_task.',
  '{\"host_op\": \"reactor-dispatch\", \"agent\": \"spec-realist\", \"prompt\": \"You are The Realist. Captain just ran a school session updating agent workspaces. Audit the changes. Use chart_search_compact to check recent changes. Use browser to GET http://localhost:8082/api/tasks to see what Captain completed. Verify accuracy. If you find errors, use chart_add to flag them and create fix tasks.\", \"telegram_chat_id\": \"8561305605\"}'
);"

log "Phase 3 task queued — Realist will audit when executor picks it up"
log "Captain school session fully queued (3 phases)"
