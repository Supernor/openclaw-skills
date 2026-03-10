#!/usr/bin/env bash
# daily-diary.sh — Trigger Historian to write and post the daily diary
# Intent: Informed, Coherent.
# Runs daily at 11pm UTC. DO NOT install cron automatically.
# Cron line (when ready): 0 23 * * * /root/.openclaw/scripts/daily-diary.sh
#
# Usage:
#   daily-diary.sh              # run diary generation
#   daily-diary.sh --dry-run    # print the prompt, don't execute

set -eo pipefail

# --- Config ---
COMPOSE_DIR="/root/openclaw"
LOG_DIR="/root/.openclaw/logs"
LOG="$LOG_DIR/daily-diary.log"
OC="/usr/local/bin/oc"
AGENT="spec-historian"
TIMEOUT=300
DATE=$(date -u +%Y-%m-%d)
DRY_RUN=false

[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

# --- Environment ---
export GOG_KEYRING_PASSWORD="openclaw-comms-keyring"
export PATH="/usr/local/bin:$PATH"

# --- Helpers ---
mkdir -p "$LOG_DIR"

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

log() {
  echo "[$(ts)] $*" >> "$LOG"
}

die() {
  log "FATAL: $*"
  echo "[$(ts)] FATAL: $*" >&2
  exit 1
}

# --- Preflight ---
command -v "$OC" >/dev/null 2>&1 || die "oc CLI not found at $OC"

# Verify gateway container is running
if ! docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps --status running 2>/dev/null | grep -q openclaw-gateway; then
  die "openclaw-gateway container is not running"
fi

# --- Prompt ---
PROMPT="Generate the daily diary for ${DATE}. Steps:
1. Gather today's activity: query recent Chartroom entries (chart_search for today's date), check agent session history, and review any reactor journal entries.
2. Write the diary in your standard format — summarize what happened, key decisions, agent activity, and anything noteworthy.
3. Post the finished diary to the Discord #daily-diary channel using the send_message tool (channel ID: 1480026250645868654).
If any step fails, still complete the remaining steps and note what failed."

# --- Execute ---
log "Daily diary triggered for $DATE"

if [ "$DRY_RUN" = true ]; then
  echo "=== DRY RUN ==="
  echo "Agent: $AGENT"
  echo "Timeout: ${TIMEOUT}s"
  echo "Prompt:"
  echo "$PROMPT"
  echo "=== Would log to: $LOG ==="
  exit 0
fi

# Call the Historian agent
log "Sending to $AGENT (timeout=${TIMEOUT}s)"
if OUTPUT=$("$OC" agent --agent "$AGENT" --message "$PROMPT" --timeout "$TIMEOUT" 2>&1 | grep -v "level=warning"); then
  log "Historian completed successfully"
  log "Output (first 500 chars): ${OUTPUT:0:500}"
else
  EXIT_CODE=$?
  log "ERROR: oc agent exited with code $EXIT_CODE"
  log "Output: ${OUTPUT:0:500}"
  # Mark output as tainted
  output-taint mark --agent "$AGENT" --reason "error" --output "${OUTPUT:0:500}" --source daily-diary 2>/dev/null || true
  # Log to health buffer for monitoring
  mkdir -p /root/.openclaw/health
  echo "{\"ts\":\"$(ts)\",\"source\":\"daily-diary\",\"status\":\"error\",\"exit_code\":$EXIT_CODE}" >> /root/.openclaw/health/buffer.jsonl 2>/dev/null || true
  exit 1
fi

# Auto-detect taint in successful output (rate limits, partial, etc.)
echo "${OUTPUT:0:500}" | output-taint auto --agent "$AGENT" --source daily-diary 2>/dev/null || true

# Log success to health buffer
mkdir -p /root/.openclaw/health
echo "{\"ts\":\"$(ts)\",\"source\":\"daily-diary\",\"status\":\"ok\",\"date\":\"$DATE\"}" >> /root/.openclaw/health/buffer.jsonl 2>/dev/null || true

log "Daily diary complete for $DATE"
