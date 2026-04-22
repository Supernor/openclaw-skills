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
  ' (' || (SELECT COUNT(*) FROM engine_usage u WHERE u.engine=e.engine AND (u.pool IS e.pool OR (u.pool IS NULL AND e.pool IS NULL)) AND REPLACE(REPLACE(u.ts, 'T', ' '), 'Z', '') > datetime('now', '-7 days')) || ' used this week)'
FROM engine_fuel e ORDER BY engine" 2>/dev/null | tr '\n' '; ')

# Recent completed tasks (what the system learned)
RECENT=$(sqlite3 /root/.openclaw/ops.db "
SELECT '#' || id || ' ' || agent || ': ' || substr(task,1,60)
FROM tasks WHERE status='completed' AND REPLACE(REPLACE(updated_at, 'T', ' '), 'Z', '') > datetime('now', '-24 hours')
ORDER BY id DESC LIMIT 10" 2>/dev/null | tr '\n' '; ')

# Active intents — what's being worked on right now (from intent system)
ACTIVE_INTENTS=$(python3 /root/.openclaw/scripts/intent-handoff.py recent --limit 5 2>/dev/null | python3 -c "
import json,sys
try:
    data = json.load(sys.stdin)
    for i in data:
        print(f\"- [{i['stage']}] {i['title']} (via {i['source_method']})\")
except: pass" 2>/dev/null)
if [ -z "$ACTIVE_INTENTS" ]; then
  ACTIVE_INTENTS="(none — check intent-handoff.py recent)"
fi

# Critical procedures from Chartroom — high-importance operational rules agents MUST know
# Why: new procedures get charted but don't reach agents until someone updates workspace files.
# This pulls them automatically so Captain can inject them during review.
# Uses chart search (vector similarity) since chart list caps at 500 and we have 900+ charts.
# Two strategies: (1) search for recent procedure/policy charts, (2) search by common topics
CRITICAL_PROCEDURES=""
for keyword in "NEVER ALWAYS procedure" "bridge restart systemctl" "policy critical operational" "decision model routing"; do
  HITS=$(/usr/local/bin/chart search "$keyword" 2>/dev/null | head -5 | awk '
    ($2 == "procedure" || $2 == "policy" || $2 == "decision") && $1+0 >= 0.5 {
      print "- (chart: " $3 ")"
    }')
  [ -n "$HITS" ] && CRITICAL_PROCEDURES="${CRITICAL_PROCEDURES}${HITS}"$'\n'
done
# Also search for charts discovered in the last 7 days (catches newly charted procedures)
RECENT_CHARTS=$(/usr/local/bin/chart search "Discovered $(date +%Y-%m)" 2>/dev/null | head -10 | awk '
  ($2 == "procedure" || $2 == "policy" || $2 == "decision" || $2 == "reading") && $1+0 >= 0.5 {
    print "- [RECENT] (chart: " $3 ")"
  }' 2>/dev/null)
[ -n "$RECENT_CHARTS" ] && CRITICAL_PROCEDURES="${CRITICAL_PROCEDURES}${RECENT_CHARTS}"$'\n'
# Deduplicate
CRITICAL_PROCEDURES=$(echo "$CRITICAL_PROCEDURES" | sort -u | grep -v "^$" | head -15)
if [ -z "$CRITICAL_PROCEDURES" ]; then
  CRITICAL_PROCEDURES="(none found — check chart search)"
fi

# Workspace freshness — which agents are most stale (priority targets for Phase 2)
STALE_AGENTS=$(python3 /root/.openclaw/scripts/workspace-freshness-scanner.py --json 2>/dev/null | python3 -c "
import json,sys
try:
    data = json.load(sys.stdin)
    results = sorted(data.get('results',[]), key=lambda x: x.get('freshness_score',10))
    for r in results[:5]:
        stale = [f for f,v in r.get('files',{}).items() if v.get('stale')]
        if stale:
            print(f\"- {r['agent_name']} ({r['agent_id']}): score={r['freshness_score']:.0f}/10, stale: {', '.join(stale)}\")
except: pass" 2>/dev/null)
if [ -z "$STALE_AGENTS" ]; then
  STALE_AGENTS="(scanner unavailable — review all agents)"
fi

# Current architecture facts
ARCH_FACTS="Task execution: host-ops-executor (systemd, 30s poll) for host_op tasks. task-runner (cron 15m) for generic tasks.
Concurrency cap: 2 system-wide. Circuit breaker: 3 failures/hour.
Self-decomposition: failed tasks output JSON subtasks.
Agents access system state via Bridge API (browser tool) at localhost:8082."

# --- Build the school briefing ---
# Priority ordered: most critical first. Agents weight top content higher.
BRIEFING="# System Update — $(date +%Y-%m-%d)

## Critical Procedures (from Chartroom — must be in agent workspaces)
These are high-importance operational rules. If any are missing from an agent's TOOLS.md, add them.
$CRITICAL_PROCEDURES

## Active Intents (what Robert is working on — context for all agents)
$ACTIVE_INTENTS

## Stale Agents (priority targets for workspace review)
$STALE_AGENTS

## Bridge (Command Center)
$BRIDGE_INFO

## Tools Available
$MCP_TOOLS

## Engines
$ENGINE_INFO

## Recent Work (last 24h)
$RECENT

## Architecture
$ARCH_FACTS

## Workspace File Rules (how to structure updates)
- Order by priority: most critical rules FIRST in each file. Agents weight top content higher.
- Include WHY for each rule: 'NEVER do X — because Y (happened N times)' is stronger than 'NEVER do X'.
- Short rules inline (5 lines or less). Longer context: add '(chart: <id>)' reference.
- Section by frequency: most-used tools/procedures first, rare stuff at bottom or chart-only."

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

# Build Phase 2 context with freshness + critical procedures data
# Write to temp file to avoid SQL quoting issues
SCHOOL_CONTEXT_FILE="/tmp/captain-school-context.txt"
cat > "$SCHOOL_CONTEXT_FILE" << 'CTXEOF'
Nightly school session — priority-driven workspace review.

WORKSPACE FILE RULES (apply to every edit you make):
1. Order by priority: most critical rules FIRST. Agents weight top content higher.
2. Include WHY: "NEVER do X — because Y (happened N times)" > "NEVER do X".
3. Short rules inline (5 lines max). Longer context: add "(chart: <id>)" reference.
4. Section by frequency: most-used procedures first, rare stuff at bottom.

STEPS (strict 15 min — stop after step 3 if time is short):
1. Read HEARTBEAT.md — it has today's critical procedures, stale agents, and active intents.
2. Pick the MOST STALE agent from the Stale Agents list. Read their TOOLS.md.
3. Check: are the critical procedures from HEARTBEAT.md present in that agent's TOOLS.md? If not, add them (with WHY and chart reference). Priority-order the file.
4. If time remains, pick the next stale agent and repeat.
5. Chart results as school-review-YYYY-MM-DD.

DO NOT: rewrite entire files. DO: surgical additions of missing critical procedures, ordered by importance.
CTXEOF

SCHOOL_CONTEXT=$(cat "$SCHOOL_CONTEXT_FILE")

# Create a task for the host-ops-executor to dispatch Captain
sqlite3 /root/.openclaw/ops.db "INSERT INTO tasks (agent, urgency, status, task, context, meta) VALUES (
  'main', 'routine', 'pending',
  'Nightly: Captain school micro-pass (strict 15m; stop after step 3). Do ONLY: 1) Read HEARTBEAT.md for critical procedures + stale agents. 2) Update the most-stale agent TOOLS.md with missing critical procedures (priority-ordered, with WHY). 3) Chart what you changed.',
  '$(echo "$SCHOOL_CONTEXT" | sed "s/'/'''/g")',
  '{\"host_op\": \"reactor-dispatch\", \"agent\": \"main\", \"prompt\": \"You are Captain. This is your nightly school session. Read your HEARTBEAT.md first — it has critical procedures from Chartroom, stale agent targets, and active intents. Pick the most-stale agent and update their TOOLS.md with missing procedures. Priority-order the file. Include WHY for each rule. Use chart references for depth. Keep changes surgical. Stop after 15 min.\", \"telegram_chat_id\": \"8561305605\"}'
);"

log "Phase 2 task queued — Captain will review most-stale agent workspace"

# --- Phase 3: Realist reviews Captain's changes ---
log "Phase 3: Dispatching Realist to audit Captain's school session"

sqlite3 /root/.openclaw/ops.db "INSERT INTO tasks (agent, urgency, status, task, context, meta) VALUES (
  'spec-realist', 'routine', 'pending',
  'Realist audit: verify Captain school changes are accurate and well-structured',
  'Captain just updated agent workspace files during the nightly school session.
Your job: verify the changes are accurate, not hallucinated, and well-structured.
Check: 1) Are procedures Captain added actually correct? Cross-reference with chart_search (read the chart, dont guess).
2) Are they priority-ordered? Most critical rules should be FIRST in the file.
3) Does each rule have a WHY? Rules without why are weak — flag them.
4) Did Captain pick the right agent? Check HEARTBEAT.md stale agents list.
5) Is the agents TOOLS.md now over 20K chars? If so, move lower-priority items to chart references.
If you find issues, chart them as issue-school-YYYY-MM-DD and create a fix task via ops_insert_task.',
  '{\"host_op\": \"reactor-dispatch\", \"agent\": \"spec-realist\", \"prompt\": \"You are The Realist. Captain just ran a school session. Audit the workspace changes for accuracy and structure. Use chart_search_compact to verify any procedures Captain added. Check priority ordering (critical first). Check that rules have WHY context. Flag missing WHY or wrong ordering. Keep your audit brief — chart issues, do not rewrite files yourself.\", \"telegram_chat_id\": \"8561305605\"}'
);"

log "Phase 3 task queued — Realist will audit when executor picks it up"
log "Captain school session fully queued (3 phases)"
