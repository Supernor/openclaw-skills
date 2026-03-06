#!/usr/bin/env bash
# model-change.sh — Dead Man's Switch for openclaw.json model changes
#
# Schedules an automatic rollback BEFORE applying the change.
# If the gateway comes up healthy, cancels the rollback.
# If it crashes, the rollback fires automatically — no human needed.
#
# Usage:
#   model-change.sh preview <agent-id> <new-model-string>
#   model-change.sh apply <agent-id> <new-model-string> [--timeout 3]
#   model-change.sh rollback                # manual rollback to latest backup
#   model-change.sh status                  # show pending at jobs
#
# Examples:
#   model-change.sh preview main "openai-codex/gpt-5.3-codex"
#   model-change.sh apply main "openai-codex/gpt-5.3-codex" --timeout 5

set -eo pipefail

CONFIG="/root/.openclaw/openclaw.json"
BACKUP_DIR="/root/.openclaw/config-backups"
COMPOSE_DIR="/root/openclaw"
LOGFILE="/root/.openclaw/logs/model-change.log"
DEFAULT_TIMEOUT=3  # minutes before auto-rollback

mkdir -p "$BACKUP_DIR" "$(dirname "$LOGFILE")"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOGFILE"; }

# --- Preview: show what would change ---
cmd_preview() {
  local agent_id="$1" new_model="$2"

  if [ -z "$agent_id" ] || [ -z "$new_model" ]; then
    echo "Usage: model-change.sh preview <agent-id> <new-model-string>"
    echo "Agent IDs: $(jq -r '.agents.list[].id' "$CONFIG" 2>/dev/null | paste -sd', ')"
    exit 1
  fi

  local current_primary current_fallbacks
  current_primary=$(jq -r --arg id "$agent_id" '.agents.list[] | select(.id == $id) | .model.primary // "(not set)"' "$CONFIG" 2>/dev/null)
  current_fallbacks=$(jq -r --arg id "$agent_id" '.agents.list[] | select(.id == $id) | .model.fallbacks // [] | join(", ")' "$CONFIG" 2>/dev/null)

  if [ -z "$current_primary" ]; then
    echo "Agent '$agent_id' not found."
    echo "Available: $(jq -r '.agents.list[].id' "$CONFIG" 2>/dev/null | paste -sd', ')"
    exit 1
  fi

  echo "=== Model Change Preview ==="
  echo "Agent:     $agent_id"
  echo "Primary:   $current_primary"
  echo "Fallbacks: $current_fallbacks"
  echo "New:       $new_model"
  echo ""

  if [ "$current_primary" = "$new_model" ]; then
    echo "No change needed — primary already set to this model."
    exit 0
  fi

  echo "To apply: model-change.sh apply $agent_id \"$new_model\""
  echo "Dead man's switch: auto-rollback in ${DEFAULT_TIMEOUT}min if gateway unhealthy."
}

# --- Apply: dead man's switch + change + test ---
cmd_apply() {
  local agent_id="$1" new_model="$2"
  shift 2 || true

  local timeout=$DEFAULT_TIMEOUT
  while [ $# -gt 0 ]; do
    case "$1" in
      --timeout) timeout="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [ -z "$agent_id" ] || [ -z "$new_model" ]; then
    echo "Usage: model-change.sh apply <agent-id> <new-model-string> [--timeout N]"
    exit 1
  fi

  local current
  current=$(jq -r --arg id "$agent_id" '.agents.list[] | select(.id == $id) | .model.primary // "(not set)"' "$CONFIG" 2>/dev/null)

  if [ -z "$current" ]; then
    log "ABORT: Agent '$agent_id' not found in config."
    exit 1
  fi

  if [ "$current" = "$new_model" ]; then
    log "No change needed — $agent_id primary already set to $new_model"
    exit 0
  fi

  # Step 1: Backup
  local backup_file="${BACKUP_DIR}/openclaw.json.$(date +%Y%m%d-%H%M%S)"
  cp "$CONFIG" "$backup_file"
  log "BACKUP: $backup_file"

  # Step 2: Schedule dead man's switch (rollback + restart)
  local rollback_script="${BACKUP_DIR}/rollback-$(date +%s).sh"
  cat > "$rollback_script" << ROLLBACK
#!/usr/bin/env bash
# Auto-rollback triggered by dead man's switch
echo "[DEAD MAN'S SWITCH] Rollback firing at \$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOGFILE"
cp "$backup_file" "$CONFIG"
cd "$COMPOSE_DIR" && docker compose restart openclaw-gateway >> "$LOGFILE" 2>&1
echo "[DEAD MAN'S SWITCH] Restored $backup_file and restarted gateway" >> "$LOGFILE"
rm -f "$rollback_script"
ROLLBACK
  chmod +x "$rollback_script"

  local at_job_id
  at_job_id=$(echo "bash $rollback_script" | at "now + $timeout minutes" 2>&1 | grep -oP 'job \K\d+')
  log "DEAD MAN'S SWITCH: at job $at_job_id — rollback in ${timeout}min if not cancelled"

  # Step 3: Apply the change
  local tmpfile="${CONFIG}.tmp.$$"
  jq --arg id "$agent_id" --arg model "$new_model" \
    '(.agents.list[] | select(.id == $id) | .model.primary) = $model' \
    "$CONFIG" > "$tmpfile"

  if ! jq '.' "$tmpfile" > /dev/null 2>&1; then
    log "ABORT: jq produced invalid JSON. Rolling back."
    rm -f "$tmpfile"
    atrm "$at_job_id" 2>/dev/null || true
    rm -f "$rollback_script"
    exit 1
  fi

  mv "$tmpfile" "$CONFIG"
  log "APPLIED: $agent_id model changed from $current to $new_model"

  # Step 4: Restart gateway
  log "RESTARTING gateway..."
  cd "$COMPOSE_DIR"
  if ! docker compose restart openclaw-gateway >> "$LOGFILE" 2>&1; then
    log "RESTART FAILED. Dead man's switch will fire in ${timeout}min."
    echo "RESTART FAILED. Rollback scheduled in ${timeout} minutes (at job $at_job_id)."
    exit 1
  fi

  # Step 5: Health check (wait for container to be ready, then check logs)
  log "HEALTH CHECK: waiting 20s for gateway to initialize..."
  sleep 20

  local health_errors
  health_errors=$(cd "$COMPOSE_DIR" && docker compose logs --tail=30 openclaw-gateway 2>&1 | grep -ci "error\|fatal\|crash\|ECONNREFUSED\|cannot find\|module not found" || true)

  if [ "$health_errors" -gt 2 ]; then
    log "HEALTH CHECK FAILED: $health_errors error indicators in last 30 log lines."
    log "Dead man's switch will fire in ~${timeout}min. Or run: model-change.sh rollback"
    echo ""
    echo "WARNING: Gateway may be unhealthy ($health_errors error indicators)."
    echo "Rollback will auto-fire in ~${timeout} minutes (at job $at_job_id)."
    echo "To rollback now:    model-change.sh rollback"
    echo "To keep the change: model-change.sh disarm"
    exit 1
  fi

  # Step 6: Success — disarm the dead man's switch
  atrm "$at_job_id" 2>/dev/null || true
  rm -f "$rollback_script"
  log "SUCCESS: Gateway healthy. Dead man's switch disarmed (at job $at_job_id removed)."
  echo ""
  echo "=== Model Change Complete ==="
  echo "Agent:    $agent_id"
  echo "Previous: $current"
  echo "New:      $new_model"
  echo "Status:   Healthy — dead man's switch disarmed"
  echo "Backup:   $backup_file"
}

# --- Rollback: manual restore from latest backup ---
cmd_rollback() {
  local latest
  latest=$(ls -t "$BACKUP_DIR"/openclaw.json.* 2>/dev/null | head -1)

  if [ -z "$latest" ]; then
    echo "No backups found in $BACKUP_DIR"
    exit 1
  fi

  log "MANUAL ROLLBACK: restoring $latest"
  cp "$latest" "$CONFIG"
  cd "$COMPOSE_DIR" && docker compose restart openclaw-gateway >> "$LOGFILE" 2>&1
  log "MANUAL ROLLBACK: complete"

  # Clear any pending at jobs
  cmd_disarm

  echo "Rolled back to: $latest"
  echo "Gateway restarting..."
}

# --- Disarm: cancel pending dead man's switch ---
cmd_disarm() {
  local cleared=0
  for script in "$BACKUP_DIR"/rollback-*.sh; do
    [ -f "$script" ] || continue
    rm -f "$script"
    cleared=$((cleared + 1))
  done

  # Cancel at jobs that reference our rollback scripts
  for job_id in $(atq 2>/dev/null | awk '{print $1}'); do
    if at -c "$job_id" 2>/dev/null | grep -q "model-change\|rollback"; then
      atrm "$job_id" 2>/dev/null || true
      cleared=$((cleared + 1))
    fi
  done

  if [ "$cleared" -gt 0 ]; then
    log "DISARMED: cleared $cleared pending rollback(s)"
    echo "Dead man's switch disarmed ($cleared items cleared)."
  else
    echo "No pending rollbacks found."
  fi
}

# --- Status: show pending at jobs ---
cmd_status() {
  echo "=== Pending At Jobs ==="
  atq 2>/dev/null || echo "(none)"
  echo ""
  echo "=== Rollback Scripts ==="
  ls -la "$BACKUP_DIR"/rollback-*.sh 2>/dev/null || echo "(none)"
  echo ""
  echo "=== Recent Backups ==="
  ls -lt "$BACKUP_DIR"/openclaw.json.* 2>/dev/null | head -5 || echo "(none)"
}

# --- Dispatch ---
case "${1:-}" in
  preview) cmd_preview "$2" "$3" ;;
  apply)   cmd_apply "$2" "$3" "${@:4}" ;;
  rollback) cmd_rollback ;;
  disarm)  cmd_disarm ;;
  status)  cmd_status ;;
  *)
    echo "model-change.sh — Dead Man's Switch for safe model changes"
    echo ""
    echo "Commands:"
    echo "  preview <agent-id> <model>     Show what would change"
    echo "  apply <agent-id> <model>       Apply with auto-rollback safety net"
    echo "  rollback                       Manual rollback to latest backup"
    echo "  disarm                         Cancel pending auto-rollback"
    echo "  status                         Show pending rollbacks and backups"
    echo ""
    echo "Options:"
    echo "  --timeout N                    Minutes before auto-rollback (default: $DEFAULT_TIMEOUT)"
    ;;
esac
