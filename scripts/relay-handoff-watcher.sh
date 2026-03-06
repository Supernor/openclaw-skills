#!/usr/bin/env bash
# relay-handoff-watcher.sh v3 — Deterministic reactor→user notification
#
# Path: direct Discord message via `openclaw message send --channel discord`
# Ops: Discord webhook to #ops-reactor (monitoring)
#
# Features:
#   - Event-driven: inotifywait on reactor.jsonl (no polling for new events)
#   - Direct Discord send: messages the user's channel
#   - CAS state machine: required → sending → sent → acked (or → failed = DLQ)
#   - Dedup: SQLite INSERT OR IGNORE under flock — no race duplicates
#   - Retry: exponential backoff (base * 2^attempts), bounded, DLQ on exhaust
#   - Reconciliation: periodic sweep detects stranded jobs and re-drives them
#   - Ack endpoint: relay-handoff-ack.sh marks handoff as received
#
# Usage:
#   relay-handoff-watcher.sh              # foreground (for systemd)
#   relay-handoff-watcher.sh --test       # process current file and exit
#   relay-handoff-watcher.sh --sweep      # run one retry sweep and exit

set -eo pipefail

BASE="/root/.openclaw"
BRIDGE="${BASE}/bridge"
EVENTS_FILE="${BRIDGE}/events/reactor.jsonl"
REACTOR_POST="${BASE}/scripts/reactor-post.sh"
LEDGER_DB="${BRIDGE}/reactor-ledger.sqlite"
LOGFILE="${BASE}/logs/relay-handoff-watcher.log"
CURSOR_FILE="${BRIDGE}/events/.handoff-cursor"
LOCKFILE="${BRIDGE}/events/.handoff-lock"
COMPOSE_DIR="/root/openclaw"

# Retry config
RETRY_INTERVAL=120     # seconds between retry sweeps
RETRY_BASE_STALE=120   # base seconds before a handoff is eligible for retry
MAX_RETRIES=3          # max retry attempts per handoff
RECONCILE_INTERVAL=300 # seconds between reconciliation sweeps

# Fallback DM channel for handoffs with no channelId
FALLBACK_DM="187662930794381312"

mkdir -p "$(dirname "$LOGFILE")" "$(dirname "$CURSOR_FILE")"
touch "$EVENTS_FILE"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOGFILE"
}

# SQL helper — fire-and-forget, never blocks reactor
sql() {
  sqlite3 "$LEDGER_DB" "$@" 2>/dev/null || true
}

# Strict SQL — used where we need return values
sql_strict() {
  sqlite3 "$LEDGER_DB" "$@" 2>/dev/null
}

# Ensure schema is current (idempotent — fresh installs get full schema from init.sql,
# but we also handle upgrades from older schemas here)
sql "CREATE TABLE IF NOT EXISTS handoff_sent (
  task_id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  sent_at TEXT NOT NULL,
  bus_id TEXT,
  acked INTEGER DEFAULT 0,
  acked_at TEXT,
  discord_sent INTEGER DEFAULT 0,
  retry_count INTEGER DEFAULT 0,
  handoff_state TEXT NOT NULL DEFAULT 'required',
  handoff_attempts INTEGER NOT NULL DEFAULT 0,
  handoff_last_error TEXT,
  handoff_updated_at TEXT
);"
# Migration for existing DBs that lack the new columns
for col in "handoff_state TEXT NOT NULL DEFAULT 'required'" "handoff_attempts INTEGER NOT NULL DEFAULT 0" "handoff_last_error TEXT" "handoff_updated_at TEXT"; do
  sqlite3 "$LEDGER_DB" "ALTER TABLE handoff_sent ADD COLUMN $col;" 2>/dev/null || true
done
sql "CREATE INDEX IF NOT EXISTS idx_handoff_state ON handoff_sent(handoff_state);"
sql "CREATE INDEX IF NOT EXISTS idx_handoff_state_attempts ON handoff_sent(handoff_state, handoff_attempts);"

# ──── Direct Discord Send ────
# Uses openclaw message send inside the container to push a message
# to the originating channel. This is the PRIMARY notification path.
# Run openclaw message send and extract JSON (filters plugin noise from stdout)
_openclaw_send() {
  local target="$1" message="$2"
  local raw
  raw=$(cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway \
    openclaw message send \
      --channel discord \
      --target "$target" \
      --message "$message" \
      --json 2>/dev/null) || true
  # Strip ANSI color codes and non-JSON lines, then parse
  echo "$raw" | sed 's/\x1b\[[0-9;]*m//g' | grep -v '^\[' | jq -c '.' 2>/dev/null || echo ""
}

discord_direct_send() {
  local channel_id="$1" message="$2"
  if [ -z "$channel_id" ]; then
    log "  -> discord-direct: no channelId, using fallback DM"
    channel_id="$FALLBACK_DM"
  fi

  # Discord channel IDs (guild channels) are 18+ digits starting with 14xxxxx (2024+).
  # User IDs from 2016-era are shorter/different ranges.
  # Strategy: try as channel first. On failure, retry with user: prefix for DM.
  local target="$channel_id"
  if [[ "$channel_id" =~ ^[0-9]+$ ]]; then
    local result
    result=$(_openclaw_send "$channel_id" "$message") || true

    local msg_id
    msg_id=$(echo "$result" | jq -r '.payload.result.messageId // empty' 2>/dev/null || echo "")
    if [ -n "$msg_id" ]; then
      log "  -> discord-direct: sent to channel ${channel_id} (msgId=${msg_id})"
      return 0
    fi

    # Channel ID failed — try as user DM
    target="user:${channel_id}"
  fi

  local result
  result=$(_openclaw_send "$target" "$message") || true

  local msg_id
  msg_id=$(echo "$result" | jq -r '.payload.result.messageId // empty' 2>/dev/null || echo "")
  if [ -n "$msg_id" ]; then
    log "  -> discord-direct: sent to ${target} (msgId=${msg_id})"
    return 0
  fi

  log "  -> discord-direct: FAILED for ${target} (result: ${result:-empty})"
  return 1
}

# ──── Baton State Machine ────
# States: required → sending → sent | failed
# CAS = compare-and-set: UPDATE only succeeds if current state matches expected.
# This prevents multiple workers from processing the same handoff.

# Insert a new handoff row in 'required' state (dedup via INSERT OR IGNORE).
# Returns 0 if this is a NEW handoff, 1 if already existed.
claim_handoff() {
  local task_id="$1" status="$2"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local safe_id
  safe_id=$(echo "$task_id" | sed "s/'/''/g")

  local changes
  changes=$(sqlite3 "$LEDGER_DB" "
    INSERT OR IGNORE INTO handoff_sent (task_id, status, sent_at, handoff_state, handoff_attempts, handoff_updated_at)
    VALUES ('$safe_id', '$status', '$ts', 'required', 0, '$ts');
    SELECT changes();
  " 2>/dev/null || echo "0")

  [ "$changes" = "1" ]
}

# CAS transition: required → sending. Returns 0 on success, 1 if another worker claimed it.
cas_acquire() {
  local task_id="$1"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local safe_id
  safe_id=$(echo "$task_id" | sed "s/'/''/g")

  local changes
  changes=$(sqlite3 "$LEDGER_DB" "
    UPDATE handoff_sent
    SET handoff_state = 'sending', handoff_updated_at = '$ts'
    WHERE task_id = '$safe_id' AND handoff_state = 'required';
    SELECT changes();
  " 2>/dev/null || echo "0")

  [ "$changes" = "1" ]
}

# Transition: sending → sent (success path)
cas_mark_sent() {
  local task_id="$1"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local safe_id
  safe_id=$(echo "$task_id" | sed "s/'/''/g")

  sql "UPDATE handoff_sent
    SET handoff_state = 'sent', discord_sent = 1, handoff_updated_at = '$ts'
    WHERE task_id = '$safe_id' AND handoff_state = 'sending';"
}

# Transition: sending → required (send failed, eligible for retry) or sending → failed (dead letter)
cas_mark_send_failed() {
  local task_id="$1" error_msg="$2"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local safe_id safe_error
  safe_id=$(echo "$task_id" | sed "s/'/''/g")
  safe_error=$(echo "$error_msg" | head -c 500 | sed "s/'/''/g")

  # Increment attempts. If exhausted → 'failed' (dead letter). Otherwise → back to 'required'.
  local new_attempts
  new_attempts=$(sqlite3 "$LEDGER_DB" "
    SELECT handoff_attempts + 1 FROM handoff_sent WHERE task_id = '$safe_id';
  " 2>/dev/null || echo "1")

  local new_state="required"
  if [ "$new_attempts" -ge "$MAX_RETRIES" ]; then
    new_state="failed"
  fi

  sql "UPDATE handoff_sent
    SET handoff_state = '$new_state',
        handoff_attempts = $new_attempts,
        handoff_last_error = '$safe_error',
        handoff_updated_at = '$ts',
        retry_count = $new_attempts
    WHERE task_id = '$safe_id' AND handoff_state = 'sending';"

  if [ "$new_state" = "failed" ]; then
    log "  DEAD-LETTER: ${task_id} — ${MAX_RETRIES} attempts exhausted"
    emit_dead_letter_event "$task_id" "$error_msg"
  fi
}

# Emit a dead-letter event to the JSONL log and ops channel
emit_dead_letter_event() {
  local task_id="$1" reason="$2"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Append dead-letter event to JSONL
  jq -n -c \
    --arg taskId "$task_id" \
    --arg status "dead-letter" \
    --arg timestamp "$ts" \
    --arg reason "$reason" \
    '{taskId: $taskId, status: "dead-letter", timestamp: $timestamp, reason: $reason, relay_handoff_required: false}' \
    >> "$EVENTS_FILE"

  # Alert ops
  if [ -x "$REACTOR_POST" ]; then
    local subject
    subject=$(sqlite3 "$LEDGER_DB" "SELECT j.subject FROM handoff_sent h LEFT JOIN jobs j ON h.task_id=j.task_id WHERE h.task_id='$(echo "$task_id" | sed "s/'/''/g")';" 2>/dev/null || echo "unknown")
    bash "$REACTOR_POST" --embed \
      "!! DEAD LETTER: ${subject}" \
      "$(printf 'Task: %s\nAll %d attempts exhausted.\nLast error: %s\nManual intervention required.' "$task_id" "$MAX_RETRIES" "${reason:0:300}")" \
      >/dev/null 2>&1 || true
  fi
}

# Build a user-facing notification message from the result
build_notification() {
  local task_id="$1" status="$2" subject="$3" duration="$4" result_summary="$5"

  local status_label="Completed"
  local status_marker="[OK]"
  case "$status" in
    fail)    status_label="Failed";      status_marker="[FAIL]" ;;
    timeout) status_label="Timed Out";   status_marker="[TIMEOUT]" ;;
  esac

  # Truncate summary for Discord (2000 char limit)
  local short_summary
  short_summary=$(echo "$result_summary" | head -c 1800)

  printf '**Reactor %s: %s**\nStatus: %s | Duration: %s\n\n%s' \
    "$status_marker" "$subject" "$status_label" "$duration" "$short_summary"
}

# ──── Process a single handoff event ────
process_handoff() {
  local line="$1"

  # Parse fields
  local task_id status subject duration channel_id
  task_id=$(echo "$line" | jq -r '.taskId // empty')
  status=$(echo "$line" | jq -r '.status // empty')
  subject=$(echo "$line" | jq -r '.subject // "unknown"')
  duration=$(echo "$line" | jq -r '.duration // "?"')
  channel_id=$(echo "$line" | jq -r '.channelId // empty')

  if [ -z "$task_id" ]; then
    log "SKIP: no taskId in event line"
    return
  fi

  # Atomic dedup: insert row in 'required' state (or skip if already exists)
  if ! claim_handoff "$task_id" "$status"; then
    log "DEDUP: handoff already claimed for ${task_id}, skipping"
    return
  fi

  # CAS: required → sending (prevents multiple workers from processing same handoff)
  if ! cas_acquire "$task_id"; then
    log "CAS-SKIP: ${task_id} — another worker already acquired this handoff"
    return
  fi

  log "HANDOFF: ${task_id} (status=${status}, subject=${subject}, channel=${channel_id:-none}, state=sending)"

  # Read result from outbox
  local result_file="${BRIDGE}/outbox/${task_id}-result.json"
  local result_summary=""
  if [ -f "$result_file" ]; then
    result_summary=$(jq -r '.summary // .reason // "Result available in outbox"' "$result_file" 2>/dev/null | head -c 2000)
  else
    result_summary="Result file not found at ${result_file}"
  fi

  # Resolve channelId from handoff artifact if missing
  if [ -z "$channel_id" ]; then
    local handoff_artifact="${BRIDGE}/outbox/${task_id}-handoff.json"
    if [ -f "$handoff_artifact" ]; then
      channel_id=$(jq -r '.channelId // empty' "$handoff_artifact" 2>/dev/null)
    fi
  fi
  # Last resort: check jobs table
  if [ -z "$channel_id" ]; then
    channel_id=$(sql_strict "SELECT channel_id FROM jobs WHERE task_id='$(echo "$task_id" | sed "s/'/''/g")';" || echo "")
  fi

  # ──── Direct Discord message to user's channel ────
  local notification
  notification=$(build_notification "$task_id" "$status" "$subject" "$duration" "$result_summary")

  local discord_ok=0
  if discord_direct_send "$channel_id" "$notification"; then
    discord_ok=1
  fi

  # ──── Ops: Discord webhook to #ops-reactor ────
  if [ -x "$REACTOR_POST" ]; then
    local status_emoji="[OK]"
    [ "$status" = "fail" ] && status_emoji="[FAIL]"
    bash "$REACTOR_POST" "Handoff ${status_emoji} **${subject}** (${task_id}) -> Relay | Duration: ${duration} | Direct: $([ $discord_ok -eq 1 ] && echo 'YES' || echo 'FAILED')" >/dev/null 2>&1 || true
    log "  -> ops-reactor ping sent"
  fi

  # ──── State Transition ────
  if [ $discord_ok -eq 1 ]; then
    cas_mark_sent "$task_id"
    sql "UPDATE jobs SET relay_handoff_sent=1 WHERE task_id='$(echo "$task_id" | sed "s/'/''/g")';"
    log "  -> Baton: sending → sent (discord_sent=1)"
  else
    cas_mark_send_failed "$task_id" "Discord direct send failed for channel ${channel_id:-unknown}"
    local new_state
    new_state=$(sqlite3 "$LEDGER_DB" "SELECT handoff_state FROM handoff_sent WHERE task_id='$(echo "$task_id" | sed "s/'/''/g")';" 2>/dev/null || echo "?")
    log "  -> Baton: sending → ${new_state} (discord failed)"
  fi
}

# ──── Retry Sweep ────
# Picks up handoffs in 'required' state that have been attempted before (failed send,
# cycled back to required). Uses CAS to prevent concurrent processing.
# Also picks up 'sent' but unacked handoffs that are stale (re-send).
retry_sweep() {
  # Part 1: Retry handoffs that failed send and are back in 'required' state
  local retry_rows
  retry_rows=$(sqlite3 -json "$LEDGER_DB" "
    SELECT h.task_id, h.status, h.sent_at, h.handoff_attempts, h.handoff_last_error,
           j.subject, j.channel_id
    FROM handoff_sent h
    LEFT JOIN jobs j ON h.task_id = j.task_id
    WHERE h.handoff_state = 'required'
      AND h.handoff_attempts > 0
      AND h.handoff_attempts < $MAX_RETRIES
      AND strftime('%s', 'now') - strftime('%s', COALESCE(h.handoff_updated_at, h.sent_at)) >
          ($RETRY_BASE_STALE * (1 << (h.handoff_attempts - 1)))
    ORDER BY h.sent_at ASC
    LIMIT 5;
  " 2>/dev/null || echo "[]")
  retry_rows="${retry_rows:-[]}"

  local count
  count=$(echo "$retry_rows" | jq 'length' 2>/dev/null || echo "0")
  count="${count:-0}"

  if [ "$count" -gt 0 ]; then
    log "RETRY-SWEEP: found ${count} handoffs in 'required' state for retry"

    echo "$retry_rows" | jq -c '.[]' 2>/dev/null | while IFS= read -r row; do
      local task_id rstatus subject channel_id attempts
      task_id=$(echo "$row" | jq -r '.task_id')
      rstatus=$(echo "$row" | jq -r '.status')
      subject=$(echo "$row" | jq -r '.subject // "unknown"')
      channel_id=$(echo "$row" | jq -r '.channel_id // empty')
      attempts=$(echo "$row" | jq -r '.handoff_attempts // 0')

      # CAS: required → sending
      if ! cas_acquire "$task_id"; then
        log "  RETRY-CAS-SKIP: ${task_id} — another worker acquired it"
        continue
      fi

      # Resolve channel from handoff artifact if jobs table had no channel
      if [ -z "$channel_id" ]; then
        local handoff_artifact="${BRIDGE}/outbox/${task_id}-handoff.json"
        if [ -f "$handoff_artifact" ]; then
          channel_id=$(jq -r '.channelId // empty' "$handoff_artifact" 2>/dev/null)
        fi
      fi

      local next_attempt=$((attempts + 1))
      log "  RETRY #${next_attempt}: ${task_id} (${subject})"

      # Re-read result
      local result_file="${BRIDGE}/outbox/${task_id}-result.json"
      local result_summary=""
      if [ -f "$result_file" ]; then
        result_summary=$(jq -r '.summary // .reason // "Result available"' "$result_file" 2>/dev/null | head -c 2000)
      fi

      # Retry direct Discord send
      local notification
      notification=$(build_notification "$task_id" "$rstatus" "$subject" "?" "$result_summary")
      notification="[RETRY #${next_attempt}] ${notification}"

      local discord_ok=0
      if discord_direct_send "$channel_id" "$notification"; then
        discord_ok=1
      fi

      if [ $discord_ok -eq 1 ]; then
        cas_mark_sent "$task_id"
        sql "UPDATE jobs SET relay_handoff_sent=1 WHERE task_id='$(echo "$task_id" | sed "s/'/''/g")';"
        log "  -> Retry success: sending → sent"
      else
        cas_mark_send_failed "$task_id" "Retry #${next_attempt} failed for channel ${channel_id:-unknown}"
        local new_state
        new_state=$(sqlite3 "$LEDGER_DB" "SELECT handoff_state FROM handoff_sent WHERE task_id='$(echo "$task_id" | sed "s/'/''/g")';" 2>/dev/null || echo "?")
        log "  -> Retry failed: sending → ${new_state}"
      fi
    done
  fi

  # Part 2: Re-send handoffs in 'sent' state that are stale (unacked) — original behavior
  local stale_sent
  stale_sent=$(sqlite3 -json "$LEDGER_DB" "
    SELECT h.task_id, h.status, h.sent_at,
           j.subject, j.channel_id
    FROM handoff_sent h
    LEFT JOIN jobs j ON h.task_id = j.task_id
    WHERE h.handoff_state = 'sent'
      AND h.acked = 0
      AND strftime('%s', 'now') - strftime('%s', COALESCE(h.handoff_updated_at, h.sent_at)) > ($RETRY_BASE_STALE * 2)
    ORDER BY h.sent_at ASC
    LIMIT 3;
  " 2>/dev/null || echo "[]")
  stale_sent="${stale_sent:-[]}"

  local stale_count
  stale_count=$(echo "$stale_sent" | jq 'length' 2>/dev/null || echo "0")
  stale_count="${stale_count:-0}"

  if [ "$stale_count" -gt 0 ]; then
    log "RETRY-SWEEP: found ${stale_count} stale 'sent' handoffs (unacked)"
    echo "$stale_sent" | jq -c '.[]' 2>/dev/null | while IFS= read -r row; do
      local task_id subject channel_id
      task_id=$(echo "$row" | jq -r '.task_id')
      subject=$(echo "$row" | jq -r '.subject // "unknown"')
      channel_id=$(echo "$row" | jq -r '.channel_id // empty')
      if [ -z "$channel_id" ]; then
        local handoff_artifact="${BRIDGE}/outbox/${task_id}-handoff.json"
        if [ -f "$handoff_artifact" ]; then
          channel_id=$(jq -r '.channelId // empty' "$handoff_artifact" 2>/dev/null)
        fi
      fi
      log "  STALE-RESEND: ${task_id} (${subject}) — sending reminder"
      discord_direct_send "$channel_id" "[REMINDER] Reactor result for **${subject}** is available. Check outbox." || true
      sql "UPDATE handoff_sent SET handoff_updated_at='$(date -u +%Y-%m-%dT%H:%M:%SZ)' WHERE task_id='$(echo "$task_id" | sed "s/'/''/g")';"
    done
  fi
}

# ──── Reconciliation Sweep ────
# Detects stranded jobs: terminal + relay_handoff_required=1 but no handoff_sent row.
# Re-emits a synthetic JSONL event so the normal consumer path picks it up.
reconciliation_sweep() {
  local stranded
  stranded=$(sqlite3 -json "$LEDGER_DB" "
    SELECT j.task_id, j.subject, j.status, j.channel_id, j.date_finished
    FROM jobs j
    LEFT JOIN handoff_sent h ON j.task_id = h.task_id
    WHERE j.relay_handoff_required = 1
      AND j.status IN ('completed', 'failed', 'timeout')
      AND h.task_id IS NULL
      AND strftime('%s','now') - strftime('%s', j.date_finished) > 60
      AND strftime('%s','now') - strftime('%s', j.date_finished) < 86400;
  " 2>/dev/null || echo "[]")
  stranded="${stranded:-[]}"

  local count
  count=$(echo "$stranded" | jq 'length' 2>/dev/null || echo "0")
  count="${count:-0}"

  if [ "$count" -gt 0 ]; then
    log "RECONCILE: found ${count} stranded job(s) — re-driving"

    echo "$stranded" | jq -c '.[]' 2>/dev/null | while IFS= read -r row; do
      local task_id subject status channel_id
      task_id=$(echo "$row" | jq -r '.task_id')
      subject=$(echo "$row" | jq -r '.subject // "unknown"')
      status=$(echo "$row" | jq -r '.status // "done"')
      channel_id=$(echo "$row" | jq -r '.channel_id // empty')

      local ts
      ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      # Re-emit synthetic event into JSONL stream
      jq -n -c \
        --arg taskId "$task_id" \
        --arg subject "$subject" \
        --arg status "$status" \
        --arg timestamp "$ts" \
        --arg channelId "${channel_id:-$FALLBACK_DM}" \
        --argjson relay_handoff true \
        '{taskId: $taskId, subject: $subject, status: $status, timestamp: $timestamp, duration: "?", relay_handoff_required: $relay_handoff, channelId: $channelId, reconciled: true}' \
        >> "$EVENTS_FILE"

      log "  RECONCILE: re-driven ${task_id} (${subject})"
    done

    # Alert ops if multiple stranded
    if [ "$count" -ge 3 ] && [ -x "$REACTOR_POST" ]; then
      bash "$REACTOR_POST" "RECONCILE: ${count} stranded handoffs re-driven — check for systemic issue" >/dev/null 2>&1 || true
    fi
  fi
}

# ──── File cursor management ────
get_file_size() {
  stat -c%s "$EVENTS_FILE" 2>/dev/null || echo "0"
}
read_cursor() {
  if [ -f "$CURSOR_FILE" ]; then
    cat "$CURSOR_FILE"
  else
    echo "0"
  fi
}
save_cursor() {
  echo "$1" > "$CURSOR_FILE"
}

# Process new lines since last cursor position (serialized via flock)
process_new_lines() {
  (
    flock -w 5 200 || { log "WARN: could not acquire lock within 5s, skipping"; return 0; }

    local cursor file_size
    cursor=$(read_cursor)
    file_size=$(get_file_size)

    # File was truncated/rotated — reset cursor
    if [ "$cursor" -gt "$file_size" ]; then
      log "File truncated (cursor=${cursor} > size=${file_size}), resetting cursor"
      cursor=0
    fi

    # Nothing new
    if [ "$cursor" -ge "$file_size" ]; then
      return
    fi

    # Read new bytes from cursor offset
    local new_lines
    new_lines=$(dd if="$EVENTS_FILE" bs=1 skip="$cursor" 2>/dev/null)

    # Update cursor BEFORE processing (prevents re-read on crash)
    save_cursor "$file_size"

    # Process each line with relay_handoff_required=true
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local handoff
      handoff=$(echo "$line" | jq -r '.relay_handoff_required // false' 2>/dev/null)
      if [ "$handoff" = "true" ]; then
        process_handoff "$line"
      fi
    done <<< "$new_lines"
  ) 200>"$LOCKFILE"
}

# ──── Main ────

# --test mode: process current file content and exit
if [ "${1:-}" = "--test" ]; then
  log "TEST MODE: processing existing events file"
  save_cursor "0"
  process_new_lines
  log "TEST MODE: done"
  exit 0
fi

# --sweep mode: run one retry sweep and exit
if [ "${1:-}" = "--sweep" ]; then
  log "SWEEP MODE: checking for stale handoffs"
  retry_sweep
  log "SWEEP MODE: done"
  exit 0
fi

log "Starting relay-handoff-watcher v3 (CAS + exponential backoff + reconciliation)"
log "Watching: ${EVENTS_FILE}"
log "Retry: every ${RETRY_INTERVAL}s, base stale ${RETRY_BASE_STALE}s (exponential), max ${MAX_RETRIES} retries"
log "Reconciliation: every ${RECONCILE_INTERVAL}s"

# On startup, process anything that accumulated while we were down
process_new_lines

# Background retry + reconciliation sweep thread
(
  local cycle=0
  while true; do
    sleep "$RETRY_INTERVAL"
    retry_sweep
    cycle=$((cycle + 1))
    # Reconciliation runs every RECONCILE_INTERVAL (~5min), which is every ~2.5 retry cycles
    if [ $((cycle * RETRY_INTERVAL)) -ge "$RECONCILE_INTERVAL" ]; then
      reconciliation_sweep
      cycle=0
    fi
  done
) &
SWEEP_PID=$!
log "Retry sweep thread started (PID=${SWEEP_PID})"

# Clean up sweep thread on exit
cleanup() {
  kill "$SWEEP_PID" 2>/dev/null || true
  wait "$SWEEP_PID" 2>/dev/null || true
  log "Watcher shutting down"
}
trap cleanup EXIT SIGTERM SIGINT SIGHUP

# Event-driven loop using inotifywait
# MODIFY fires when bridge-reactor.sh appends to the JSONL file
inotifywait --monitor --event modify --format '%w%f' "$EVENTS_FILE" 2>/dev/null | while read -r _changed_file; do
  process_new_lines
done

# If inotifywait exits (shouldn't happen), log and exit non-zero so systemd restarts us
log "ERROR: inotifywait exited unexpectedly"
exit 1
