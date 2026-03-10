#!/usr/bin/env bash
# ai-news.sh — Daily AI news digest via Research agent
# Intent: Informed, Resourceful.
# Runs daily at 8:30am UTC (after transcript auto-ingest at 8am).
# Uses the Research agent's ai-news skill with Gemini web search.
#
# Usage:
#   ai-news.sh              # run digest
#   ai-news.sh --dry-run    # show what would be sent without executing

set -eo pipefail

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

COMPOSE_DIR="/root/openclaw"
LOG_DIR="/root/.openclaw/logs"
LOGFILE="$LOG_DIR/ai-news.log"
HEALTH_DIR="/root/.openclaw/health"
AGENT="spec-research"
TIMEOUT=300

mkdir -p "$LOG_DIR" "$HEALTH_DIR"

# GOG_KEYRING_PASSWORD needed for any Google Workspace integration
export GOG_KEYRING_PASSWORD="openclaw-comms-keyring"

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "[$(ts)] $*" | tee -a "$LOGFILE"; }

log "Starting AI news digest"

OC="/usr/local/bin/oc"

# Verify oc CLI and gateway
command -v "$OC" >/dev/null 2>&1 || { log "ERROR: oc CLI not found"; exit 1; }
if ! docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps --status running 2>/dev/null | grep -q openclaw-gateway; then
  log "ERROR: Gateway not running — aborting"
  echo "{\"ts\":\"$(ts)\",\"source\":\"ai-news\",\"status\":\"error\",\"reason\":\"gateway-not-running\"}" >> "$HEALTH_DIR/buffer.jsonl"
  exit 1
fi

# Build the prompt — explicit instructions to constrain agent behavior
PROMPT="Use your ai-news skill now. Use Gemini web search to find today's AI news ($(date -u +%Y-%m-%d)). Focus on:

1. New model releases and benchmarks (OpenAI, Anthropic, Google, Meta, Mistral, others)
2. Pricing changes or API updates from any major provider
3. Infrastructure and tooling news (MCP, LangChain, vector DBs, hosting)
4. Anything that could affect OpenClaw's model routing (currently Codex primary, Gemini Flash fallback)
5. Open-source model releases or license changes

Produce a concise digest — bullet points, no filler. If you find anything actionable for OpenClaw (model deprecation, new cheaper model, API change), chart it using chart_add with category 'reading' and an ID like 'reading-ai-news-YYYY-MM-DD-<topic>'.

IMPORTANT: Do NOT run any local commands. Use Gemini web search only."

if [ "$DRY_RUN" = true ]; then
  log "DRY RUN — would send to $AGENT:"
  echo "$PROMPT" | tee -a "$LOGFILE"
  exit 0
fi

# Fire the agent
log "Sending to $AGENT (timeout=${TIMEOUT}s)..."
if OUTPUT=$("$OC" agent --agent "$AGENT" --message "$PROMPT" --timeout "$TIMEOUT" 2>&1 | grep -v "level=warning"); then
  log "Research agent completed successfully"
  log "Output (first 500 chars): ${OUTPUT:0:500}"
else
  EXIT_CODE=$?
  log "ERROR: oc agent exited with code $EXIT_CODE"
  log "Output: ${OUTPUT:0:500}"
  # Mark output as tainted
  output-taint mark --agent "$AGENT" --reason "error" --output "${OUTPUT:0:500}" --source ai-news 2>/dev/null || true
  echo "{\"ts\":\"$(ts)\",\"source\":\"ai-news\",\"status\":\"error\",\"exit_code\":$EXIT_CODE}" >> "$HEALTH_DIR/buffer.jsonl"
  exit 1
fi

# Auto-detect taint in successful output (rate limits, partial, etc.)
echo "${OUTPUT:0:500}" | output-taint auto --agent "$AGENT" --source ai-news 2>/dev/null || true

# Write health event
echo "{\"ts\":\"$(ts)\",\"source\":\"ai-news\",\"status\":\"ok\",\"chars\":${#OUTPUT}}" >> "$HEALTH_DIR/buffer.jsonl"

log "AI news digest complete"
