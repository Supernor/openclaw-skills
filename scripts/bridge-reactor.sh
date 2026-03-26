#!/usr/bin/env bash
# bridge-reactor.sh — Host-side watcher that connects the Bridge
# Polls inbox for tasks, invokes Claude Code CLI, writes results to outbox.
# Runs on the HOST (not in the container) because claude CLI lives here.
#
# Features:
#   - Activity-based timeout: kills claude -p after 10min of no stdout output
#   - Discord progress streaming: posts progress markers to #ops-reactor
#   - Completion notifications: posts success/failure embeds to #ops-reactor
#   - Chartroom-aware prompt: tells Claude Code how to search the Chartroom
#   - Reliability guard: stuck in-progress tasks are force-failed on unexpected exit
#   - Event stream: JSONL lifecycle events at bridge/events/reactor.jsonl
#
# Usage:
#   bridge-reactor.sh              # foreground
#   bridge-reactor.sh --once       # process one batch and exit (for testing)

set -eo pipefail

BASE="/root/.openclaw"
BRIDGE="${BASE}/bridge"
INBOX="${BRIDGE}/inbox"
OUTBOX="${BRIDGE}/outbox"
EVENTS_DIR="${BRIDGE}/events"
EVENTS_FILE="${EVENTS_DIR}/reactor.jsonl"
BRIDGE_SH="${BASE}/scripts/bridge.sh"
REACTOR_POST="${BASE}/scripts/reactor-post.sh"
LOGFILE="${BASE}/logs/reactor.log"
POLL_INTERVAL=10
INACTIVITY_TIMEOUT=600  # 10 minutes of no output = stuck
CHUNK_MAX_WALL=300      # 5 minutes wall-clock max per task chunk (full confidence)
CHUNK_MIN_WALL=120      # 2 minutes wall-clock (limp mode after recovery)
MAX_CHUNKS=6            # Max continuation chunks before giving up (30min total)
LEDGER_DB="${BRIDGE}/reactor-ledger.sqlite"

# Rate-limit / consecutive failure tracking
CONSECUTIVE_FAILS=0
CONSECUTIVE_SUCCESSES=0         # Tracks recovery ramp-up after backoff
MAX_CONSECUTIVE_FAILS=3         # After 3 fails in a row, assume rate limit
RAMP_UP_THRESHOLD=2             # Successes needed to return to full chunk size
BACKOFF_BASE=60                 # Start at 60s
BACKOFF_MAX=1800                # Cap at 30 minutes
BACKOFF_FILE="${BRIDGE}/.reactor-backoff"       # Persists across restarts
LIMP_MODE_FILE="${BRIDGE}/.reactor-limp-mode"   # Present = running shorter chunks

mkdir -p "$INBOX" "$OUTBOX" "$EVENTS_DIR" "$(dirname "$LOGFILE")"

# Initialize ledger DB if missing
if [ ! -f "$LEDGER_DB" ]; then
  sqlite3 "$LEDGER_DB" < "${BASE}/scripts/reactor-ledger-init.sql"
  log "Initialized SQLite ledger at ${LEDGER_DB}"
fi

# SQL helper — fire-and-forget, never blocks reactor
sql() {
  sqlite3 "$LEDGER_DB" "$@" 2>/dev/null || true
}

# Ledger: insert new job row
ledger_job_received() {
  local task_id="$1" subject="$2" priority="$3" requested_by="$4" ts="$5" chan_id="${6:-}"
  sql "INSERT OR IGNORE INTO jobs (task_id, subject, priority, requested_by, date_received, status, channel_id) VALUES ('$(echo "$task_id" | sed "s/'/''/g")', '$(echo "$subject" | sed "s/'/''/g")', '$(echo "$priority" | sed "s/'/''/g")', '$(echo "$requested_by" | sed "s/'/''/g")', '$ts', 'pending', NULLIF('$(echo "$chan_id" | sed "s/'/''/g")',''));"
}

# Ledger: mark job started
ledger_job_started() {
  local task_id="$1" ts="$2"
  sql "UPDATE jobs SET status='in-progress', date_started='$ts' WHERE task_id='$(echo "$task_id" | sed "s/'/''/g")';"
}

# Ledger: mark job finished (success or fail)
ledger_job_finished() {
  local task_id="$1" status="$2" ts="$3" duration_secs="$4" exit_code="${5:-}" tool_count="${6:-0}" result_preview="${7:-}"
  local safe_preview
  safe_preview=$(echo "$result_preview" | head -c 500 | sed "s/'/''/g")
  sql "UPDATE jobs SET status='$status', date_finished='$ts', duration_seconds=$duration_secs, exit_code=${exit_code:-NULL}, tool_count=$tool_count, result_preview='$safe_preview', relay_handoff_required=1 WHERE task_id='$(echo "$task_id" | sed "s/'/''/g")';"
}

# Ledger: insert event
ledger_event() {
  local task_id="$1" event_type="$2" ts="$3" payload="${4:-}"
  local safe_payload
  safe_payload=$(echo "$payload" | sed "s/'/''/g")
  sql "INSERT INTO events (task_id, event_type, ts, payload_json) VALUES ('$(echo "$task_id" | sed "s/'/''/g")', '$event_type', '$ts', '$safe_payload');"
}

# Extract a markdown section by heading (## Heading or **Heading**)
# Returns content between the heading and the next heading of equal/higher level, or EOF.
extract_section() {
  local text="$1" heading="$2"
  # Try ## Heading first, then **Heading**
  echo "$text" | awk -v h="$heading" '
    BEGIN { found=0; IGNORECASE=1 }
    /^##+ / {
      if (found) exit
      gsub(/^#+[ \t]*/, "")
      if (tolower($0) ~ tolower(h)) { found=1; next }
    }
    /^\*\*[^*]+\*\*/ {
      if (found) exit
      line=$0; gsub(/^\*\*/, "", line); gsub(/\*\*.*/, "", line)
      if (tolower(line) ~ tolower(h)) { found=1; next }
    }
    found { print }
  ' | sed '/^$/d' | head -c 2000
}

# Parse result text and populate questions, feedback, retros tables
ledger_populate_from_result() {
  local task_id="$1" result_text="$2" ts="$3"
  local safe_task_id
  safe_task_id=$(echo "$task_id" | sed "s/'/''/g")

  # --- Retros: extract Wins, Losses, Learnings sections ---
  local wins losses learnings
  wins=$(extract_section "$result_text" "wins")
  losses=$(extract_section "$result_text" "losses")
  learnings=$(extract_section "$result_text" "learnings")

  # If no structured sections, try single-line markers: "Win:", "Loss:", "Learning:"
  if [ -z "$wins" ]; then
    wins=$(echo "$result_text" | grep -i '^[*-]*\s*win[s]*:' | head -5 | sed 's/^[*-]*\s*//' || true)
  fi
  if [ -z "$losses" ]; then
    losses=$(echo "$result_text" | grep -i '^[*-]*\s*loss\|^[*-]*\s*limitation' | head -5 | sed 's/^[*-]*\s*//' || true)
  fi
  if [ -z "$learnings" ]; then
    learnings=$(echo "$result_text" | grep -i '^[*-]*\s*learning[s]*:' | head -5 | sed 's/^[*-]*\s*//' || true)
  fi

  # Always write a retro row (nulls are fine — the row existing means "processed")
  local safe_wins safe_losses safe_learnings
  safe_wins=$(echo "$wins" | head -c 1000 | sed "s/'/''/g")
  safe_losses=$(echo "$losses" | head -c 1000 | sed "s/'/''/g")
  safe_learnings=$(echo "$learnings" | head -c 1000 | sed "s/'/''/g")
  sql "INSERT INTO retros (task_id, wins, losses, learnings, created_at) VALUES ('$safe_task_id', NULLIF('$safe_wins',''), NULLIF('$safe_losses',''), NULLIF('$safe_learnings',''), '$ts');"

  # --- Questions: look for clarification markers ---
  local questions_text
  questions_text=$(extract_section "$result_text" "question")
  if [ -z "$questions_text" ]; then
    # Try lines starting with "?" or "Clarification:"
    questions_text=$(echo "$result_text" | grep -E '^\?|^[*-]*\s*[Cc]larification' | head -5 || true)
  fi
  if [ -n "$questions_text" ]; then
    # Write each non-empty line as a separate question
    while IFS= read -r qline; do
      qline=$(echo "$qline" | sed 's/^[*-]*\s*//' | sed 's/^?//' | xargs)
      [ -z "$qline" ] && continue
      local safe_q
      safe_q=$(echo "$qline" | head -c 500 | sed "s/'/''/g")
      sql "INSERT INTO questions (task_id, question_text, to_role, answered, created_at) VALUES ('$safe_task_id', '$safe_q', 'requesting_agent', 0, '$ts');"
    done <<< "$questions_text"
  fi

  # --- Feedback: look for feedback section ---
  local feedback_text
  feedback_text=$(extract_section "$result_text" "feedback")
  if [ -z "$feedback_text" ]; then
    feedback_text=$(extract_section "$result_text" "recommendation")
  fi
  if [ -n "$feedback_text" ]; then
    local safe_fb
    safe_fb=$(echo "$feedback_text" | head -c 1000 | sed "s/'/''/g")
    sql "INSERT INTO feedback (task_id, feedback_to_openclaw, created_at) VALUES ('$safe_task_id', '$safe_fb', '$ts');"
  fi
}

# Emit compact handoff payload file for Relay human-facing delivery
# Called on every terminal event (success, fail, timeout, force-fail)
emit_handoff_artifact() {
  local task_id="$1" status="$2" subject="$3" duration="$4" next_action="${5:-relay-notify}"
  local summary_text="${6:-}" channel_id="${7:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local safe_summary
  safe_summary=$(echo "$summary_text" | head -c 500)

  jq -n -c \
    --arg task_id "$task_id" \
    --arg status "$status" \
    --arg subject "$subject" \
    --arg duration "$duration" \
    --arg next_action "$next_action" \
    --arg summary "$safe_summary" \
    --arg created "$ts" \
    --arg channel_id "$channel_id" \
    --argjson relay_handoff_required true \
    '{task_id: $task_id, status: $status, subject: $subject, duration: $duration, summary: $summary, next_action: $next_action, relay_handoff_required: $relay_handoff_required, created: $created, channelId: (if $channel_id != "" then $channel_id else null end)}' \
    > "${OUTBOX}/${task_id}-handoff.json"
  log "HANDOFF-ARTIFACT: written ${OUTBOX}/${task_id}-handoff.json"
}

# Enqueue a follow-up task into the reactor inbox (self-enqueue for continuity)
enqueue_followup() {
  local follow_id="$1" subject="$2" description="$3" priority="${4:-low}" requested_by="${5:-reactor}"
  local ts ts_prefix
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  ts_prefix=$(echo "$ts" | sed 's/:/-/g')

  jq -n \
    --arg id "$follow_id" \
    --arg created "$ts" \
    --arg from "$requested_by" \
    --arg to "reactor" \
    --arg priority "$priority" \
    --arg subject "$subject" \
    --arg description "$description" \
    '{id: $id, dbId: "self-enqueue", created: $created, from: $from, to: $to, priority: $priority, subject: $subject, description: $description, files: [], status: "pending"}' \
    > "${INBOX}/${ts_prefix}-${follow_id}.json"
  log "SELF-ENQUEUE: ${follow_id} -> ${INBOX}/${ts_prefix}-${follow_id}.json"
}

# Track the active task file so the guard can clean up on unexpected exit
_REACTOR_ACTIVE_TASKFILE=""
_REACTOR_ACTIVE_TASKID=""
_REACTOR_ACTIVE_SUBJECT=""
_REACTOR_ACTIVE_CHANNEL=""
_REACTOR_START_TIME=""

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOGFILE"
}

# Post to #ops-reactor (non-blocking, best-effort)
discord_post() {
  bash "$REACTOR_POST" "$@" >/dev/null 2>&1 || true
}

discord_embed() {
  bash "$REACTOR_POST" --embed "$@" >/dev/null 2>&1 || true
}

# Emit structured JSONL lifecycle event
# Terminal statuses (done, fail) get relay_handoff_required=true as a race-gunshot marker
emit_event() {
  local task_id="$1" subject="$2" status="$3" duration="${4:-}" channel_id="${5:-}"
  local ts handoff="false"
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # Terminal events signal Relay to immediately pick up the result
  case "$status" in done|fail) handoff="true" ;; esac
  jq -n -c \
    --arg taskId "$task_id" \
    --arg subject "$subject" \
    --arg status "$status" \
    --arg timestamp "$ts" \
    --arg duration "$duration" \
    --arg channelId "$channel_id" \
    --argjson relay_handoff "$handoff" \
    '{taskId: $taskId, subject: $subject, status: $status, timestamp: $timestamp, duration: (if $duration != "" then $duration else null end), relay_handoff_required: $relay_handoff, channelId: (if $channelId != "" then $channelId else null end)}' \
    >> "$EVENTS_FILE"
}

# Format elapsed seconds as human-readable duration
format_duration() {
  local secs="$1"
  if [ "$secs" -lt 60 ]; then
    echo "${secs}s"
  elif [ "$secs" -lt 3600 ]; then
    echo "$((secs / 60))m $((secs % 60))s"
  else
    echo "$((secs / 3600))h $((secs % 3600 / 60))m"
  fi
}

# Force-fail a stuck in-progress task (called by guard and trap)
force_fail_task() {
  local taskfile="$1" task_id="$2" subject="$3" start_time="$4" reason="$5" ff_channel="${6:-$_REACTOR_ACTIVE_CHANNEL}"
  [ -f "$taskfile" ] || return 0

  local now end_time duration_secs duration_str
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  end_time=$(date +%s)
  duration_secs=0
  if [ -n "$start_time" ] && [ "$start_time" -gt 0 ] 2>/dev/null; then
    duration_secs=$(( end_time - start_time ))
  fi
  duration_str=$(format_duration "$duration_secs")

  log "FORCE-FAIL: ${task_id} — ${reason}"

  jq -n \
    --arg id "${task_id}-result" \
    --arg taskId "$task_id" \
    --arg created "$now" \
    --arg from "reactor" \
    --arg duration "$duration_str" \
    --arg reason "$reason" \
    '{id: $id, taskId: $taskId, created: $created, from: $from, status: "failed", duration: $duration, reason: $reason, relay_handoff_required: true}' \
    > "${OUTBOX}/${task_id}-result.json"

  mv "$taskfile" "${OUTBOX}/${task_id}-task.json" 2>/dev/null || true

  emit_event "$task_id" "$subject" "fail" "$duration_str" "$ff_channel"
  ledger_job_finished "$task_id" "failed" "$now" "$duration_secs" "" "0" "Force-failed: ${reason}"
  ledger_event "$task_id" "force-fail" "$now" "{\"reason\":\"$(echo "$reason" | sed 's/"/\\"/g')\",\"relay_handoff_required\":true}"
  emit_handoff_artifact "$task_id" "force-failed" "$subject" "$duration_str" "relay-notify-failure" "Force-failed: ${reason}" "$ff_channel"
  discord_embed "!! Reactor: ${subject}" "$(printf '**Status:** Force-failed (guard)\n**Duration:** %s\n**Reason:** %s' "$duration_str" "$reason")"
}

# Trap handler: if the script is killed while a task is in-progress, force-fail it
_reactor_cleanup() {
  if [ -n "$_REACTOR_ACTIVE_TASKFILE" ] && [ -f "$_REACTOR_ACTIVE_TASKFILE" ]; then
    force_fail_task "$_REACTOR_ACTIVE_TASKFILE" "$_REACTOR_ACTIVE_TASKID" "$_REACTOR_ACTIVE_SUBJECT" "$_REACTOR_START_TIME" "Reactor process terminated unexpectedly (signal/crash)"
  fi
  exit 1
}
trap _reactor_cleanup SIGTERM SIGINT SIGHUP

process_task() {
  local taskfile="$1"
  local task_id subject description to priority files_json status channel_id

  task_id=$(jq -r '.id' "$taskfile")
  subject=$(jq -r '.subject' "$taskfile")
  description=$(jq -r '.description // ""' "$taskfile")
  to=$(jq -r '.to' "$taskfile")
  priority=$(jq -r '.priority // "normal"' "$taskfile")
  files_json=$(jq -r '.files // [] | join(", ")' "$taskfile")
  status=$(jq -r '.status' "$taskfile")
  channel_id=$(jq -r '.channelId // .channel_id // ""' "$taskfile")
  local chunk prior_progress original_task_id
  chunk=$(jq -r '.chunk // 1' "$taskfile")
  prior_progress=$(jq -r '.prior_progress // ""' "$taskfile")
  original_task_id=$(jq -r '.original_task_id // .id' "$taskfile")

  # Only process pending tasks
  if [ "$status" != "pending" ]; then
    return 0
  fi

  # Refuse if chunk limit exceeded (prevents infinite continuation loops)
  if [ "$chunk" -gt "$MAX_CHUNKS" ]; then
    log "CHUNK_LIMIT: ${task_id} — chunk ${chunk} exceeds max ${MAX_CHUNKS}. Failing task."
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
      --arg id "${task_id}-result" \
      --arg taskId "$task_id" \
      --arg created "$now" \
      --arg from "reactor" \
      --arg reason "Exceeded max chunk limit (${MAX_CHUNKS}). Total wall time: ~$(( MAX_CHUNKS * CHUNK_MAX_WALL / 60 ))min. Prior progress included in this result." \
      --arg progress "$prior_progress" \
      '{id: $id, taskId: $taskId, created: $created, from: $from, status: "failed", reason: $reason, prior_progress: $progress, relay_handoff_required: true}' \
      > "${OUTBOX}/${task_id}-result.json"
    mv "$taskfile" "${OUTBOX}/${task_id}-task.json"
    discord_embed "X Reactor: ${subject}" "$(printf '**Status:** Chunk limit reached (%d/%d)\n**Total budget:** ~%dmin\nPrior progress preserved in result.' "$chunk" "$MAX_CHUNKS" "$(( MAX_CHUNKS * CHUNK_MAX_WALL / 60 ))")"
    return 1
  fi

  # Register active task for guard/trap
  _REACTOR_ACTIVE_TASKFILE="$taskfile"
  _REACTOR_ACTIVE_TASKID="$task_id"
  _REACTOR_ACTIVE_SUBJECT="$subject"
  _REACTOR_ACTIVE_CHANNEL="$channel_id"
  _REACTOR_START_TIME=$(date +%s)

  local received_ts
  received_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  log "PICKUP: ${task_id} — ${subject} (for: ${to}, priority: ${priority}, channel: ${channel_id:-none})"
  emit_event "$task_id" "$subject" "pickup" "" "$channel_id"
  ledger_job_received "$task_id" "$subject" "$priority" "$to" "$received_ts" "$channel_id"

  # Mark as in-progress
  jq '.status = "in-progress"' "$taskfile" > "${taskfile}.tmp" && mv "${taskfile}.tmp" "$taskfile"

  local started_ts
  started_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  ledger_job_started "$task_id" "$started_ts"
  ledger_event "$task_id" "pickup" "$started_ts"

  # Notify Discord: task started
  discord_embed "Reactor: ${subject}" "Task picked up. Working..."

  # Record start time
  local start_time
  start_time=$_REACTOR_START_TIME

  # Compute effective chunk duration (shorter in limp mode after rate-limit recovery)
  local effective_chunk_wall
  effective_chunk_wall=$(get_chunk_wall)

  # === Build the prompt for Claude Code (Bug 2: enriched with system context) ===
  local prompt="You are the Reactor — Claude Code powering the OpenClaw system.
An OpenClaw agent has sent you a task via the bridge.

Task: ${subject}
Details: ${description}
Requesting agent: ${to}
Priority: ${priority}"

  if [ -n "$files_json" ] && [ "$files_json" != "" ]; then
    prompt="${prompt}
Relevant files: ${files_json}"
  fi

  # Add continuation context if this is a follow-up chunk
  if [ "$chunk" -gt 1 ] && [ -n "$prior_progress" ]; then
    prompt="${prompt}

## CONTINUATION — Chunk ${chunk} of ${MAX_CHUNKS}
This is a continuation of a previous chunk that ran out of time.
Pick up where the previous chunk left off. Do NOT redo work already completed.

### Prior Progress (from chunk $(( chunk - 1 ))):
${prior_progress}"
  fi

  prompt="${prompt}

## Working Directory
Work from /root/.openclaw/ as your base. You have access to the full OpenClaw deployment.
The Docker compose project is at /root/openclaw/.

## Chartroom Access
To search the Chartroom (shared crew knowledge), run:
  docker compose exec openclaw-gateway openclaw ltm search '<keywords>'
from /root/openclaw/. Search before troubleshooting — error charts contain known fixes.
To list all charts: docker compose exec openclaw-gateway openclaw ltm list
To read a specific chart: docker compose exec openclaw-gateway openclaw ltm read '<id>'

## Autonomy Policy
You operate under a confidence-based autonomy policy:
1. **Clarifications go to the requesting agent, not the human.** If you need more info, return a concise clarification question as your result. The requesting agent (shown above) will relay it. Never address the human directly.
2. **Confidence >= 80% AND action is reversible:** Proceed automatically. Do the work, return results.
3. **Confidence < 80% OR action is hard to reverse (destructive git ops, config overwrites, infra changes):** STOP. Return exactly ONE concise clarification question as your result. Do not attempt the action.
4. **Serialized lane:** Each task is request -> result -> next request. Do not batch or combine tasks.

## Time Budget
You have a ${effective_chunk_wall}-second (~$(( effective_chunk_wall / 60 ))min) wall-clock budget for this chunk.
This is chunk ${chunk} of up to ${MAX_CHUNKS}. Work incrementally:
- Focus on the highest-impact actions first.
- If you finish early, great — return your results.
- If you're mid-task when time runs out, your partial output is preserved and a continuation chunk will pick up where you left off. Structure your output so partial results are useful.
- Prefer completing a few things well over starting many things.

## Response
Be concise. Return actionable results the agent can relay to the user.
If you create or modify files, list the paths and a one-line summary of each change."

  # === Run Claude Code with monitored execution ===
  # Uses --output-format stream-json for structured progress events.
  # Parses tool_use events -> posts tool names to Discord as progress.
  # Accumulates text_delta events -> builds final result text.
  # Watchdog kills claude if no output for INACTIVITY_TIMEOUT seconds.

  local raw_stream_file result_file heartbeat_file claude_pid_file
  raw_stream_file=$(mktemp /tmp/reactor-stream.XXXXXX)
  result_file=$(mktemp /tmp/reactor-result.XXXXXX)
  heartbeat_file=$(mktemp /tmp/reactor-heartbeat.XXXXXX)
  claude_pid_file=$(mktemp /tmp/reactor-claude-pid.XXXXXX)
  touch "$heartbeat_file"
  local tool_count=0

  log "RUNNING claude -p for task ${task_id}..."
  emit_event "$task_id" "$subject" "running" "" "$channel_id"
  ledger_event "$task_id" "running" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Launch claude -p with stream-json, piped through a parser
  (
    claude -p "$prompt" \
      --output-format stream-json \
      --verbose \
      --allowedTools "Read,Glob,Grep,Edit,Write,Bash" \
      --add-dir /root/.openclaw \
      --add-dir /root/openclaw \
      --no-session-persistence \
      2>> "$LOGFILE" &
    CLAUDE_INNER_PID=$!
    echo "$CLAUDE_INNER_PID" > "$claude_pid_file"
    wait "$CLAUDE_INNER_PID"
  ) | while IFS= read -r line; do
    # Every line of output = heartbeat
    touch "$heartbeat_file"

    # Save raw stream for debugging (first 50 lines only to avoid bloat)
    local stream_lines
    stream_lines=$(wc -l < "$raw_stream_file" 2>/dev/null || echo 0)
    if [ "$stream_lines" -lt 50 ]; then
      echo "$line" >> "$raw_stream_file"
    fi

    # Skip non-JSON lines (stderr leaks, empty lines)
    if ! echo "$line" | jq -e '.' >/dev/null 2>&1; then
      continue
    fi

    # Claude Code stream-json format (verified from actual output):
    #   {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read",...}]}} — tool calls
    #   {"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}} — text response
    #   {"type":"result","result":"final text"} — final result with full text
    #   {"type":"user",...} — tool results (ignore)
    #   {"type":"system",...} — init (ignore)

    local event_type
    event_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)

    case "$event_type" in
      assistant)
        # Check for tool_use blocks in the assistant message
        local tool_names
        tool_names=$(echo "$line" | jq -r '
          [.message.content[]? | select(.type == "tool_use") | .name] | join(",")
        ' 2>/dev/null)
        if [ -n "$tool_names" ] && [ "$tool_names" != "null" ]; then
          # Post each tool to Discord
          IFS=',' read -ra tools <<< "$tool_names"
          for tn in "${tools[@]}"; do
            tool_count=$((tool_count + 1))
            discord_post ":: ${subject} — using ${tn} (#${tool_count})" &
            log "  TOOL: ${task_id} — ${tn} (#${tool_count})"
            sqlite3 "$LEDGER_DB" "INSERT INTO events (task_id, event_type, ts, payload_json) VALUES ('$task_id', 'tool_use', '$(date -u +%Y-%m-%dT%H:%M:%SZ)', '{\"tool\":\"$tn\",\"seq\":$tool_count}');" 2>/dev/null || true
            # Emit progress event every 5 tools for Telegram notifications
            if (( tool_count % 5 == 0 )); then
              local progress_ts
              progress_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
              jq -n -c \
                --arg taskId "$task_id" \
                --arg subject "$subject" \
                --arg timestamp "$progress_ts" \
                --arg channelId "$channel_id" \
                --argjson toolCount "$tool_count" \
                '{taskId: $taskId, subject: $subject, status: "progress", timestamp: $timestamp, toolCount: $toolCount, relay_handoff_required: false, channelId: (if $channelId != "" then $channelId else null end)}' \
                >> "$EVENTS_FILE" &
            fi
          done
        fi
        ;;
      result)
        # Final result — .result contains the full assistant text
        local result_text_from_event
        result_text_from_event=$(echo "$line" | jq -r '.result // empty' 2>/dev/null)
        if [ -n "$result_text_from_event" ]; then
          printf '%s' "$result_text_from_event" > "$result_file"
        fi
        ;;
    esac
  done &
  local pipe_pid=$!

  # Background watchdog: kill on inactivity OR wall-clock chunk expiry
  (
    while kill -0 "$pipe_pid" 2>/dev/null; do
      local last_beat now_epoch idle wall_elapsed
      last_beat=$(stat -c %Y "$heartbeat_file" 2>/dev/null || echo 0)
      now_epoch=$(date +%s)
      idle=$(( now_epoch - last_beat ))
      wall_elapsed=$(( now_epoch - start_time ))

      # Wall-clock chunk limit (graceful — progress is preserved)
      if [ "$wall_elapsed" -ge "$effective_chunk_wall" ]; then
        log "CHUNK_EXPIRE: ${task_id} — wall-clock limit ${effective_chunk_wall}s reached (chunk ${chunk}/${MAX_CHUNKS}), stopping"
        local claude_pid
        claude_pid=$(cat "$claude_pid_file" 2>/dev/null || echo "")
        if [ -n "$claude_pid" ]; then
          pkill -P "$claude_pid" 2>/dev/null || true
          kill "$claude_pid" 2>/dev/null || true
        fi
        kill "$pipe_pid" 2>/dev/null || true
        echo "REACTOR_CHUNK_EXPIRE" > "${result_file}.chunk_expire"
        break
      fi

      # Inactivity timeout (stuck — no useful output)
      if [ "$idle" -ge "$INACTIVITY_TIMEOUT" ]; then
        log "TIMEOUT: ${task_id} — no output for ${idle}s, killing claude process"
        local claude_pid
        claude_pid=$(cat "$claude_pid_file" 2>/dev/null || echo "")
        if [ -n "$claude_pid" ]; then
          pkill -P "$claude_pid" 2>/dev/null || true
          kill "$claude_pid" 2>/dev/null || true
        fi
        kill "$pipe_pid" 2>/dev/null || true
        echo "REACTOR_TIMEOUT" > "${result_file}.timeout"
        break
      fi
      sleep 30
    done
  ) &
  local watchdog_pid=$!

  # Wait for pipeline to finish
  wait "$pipe_pid" 2>/dev/null
  local exit_code=$?

  # Clean up watchdog
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true

  # Read result text (accumulated from text_delta events)
  local result_text
  result_text=$(cat "$result_file" 2>/dev/null || echo "")

  # Check if result_text is empty — fall back to raw stream extraction
  if [ -z "$result_text" ] && [ -f "$raw_stream_file" ]; then
    # Try extracting from result events in the raw stream
    result_text=$(grep '"type":"result"' "$raw_stream_file" 2>/dev/null | tail -1 | jq -r '.result // empty' 2>/dev/null || echo "")
    if [ -z "$result_text" ]; then
      result_text="(No text output captured. Check raw stream at ${raw_stream_file})"
    fi
  fi

  # Recover tool_count from SQLite (subshell variable doesn't propagate)
  tool_count=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM events WHERE task_id='$task_id' AND event_type='tool_use';" 2>/dev/null || echo 0)

  # Check for timeout or chunk expiry
  local timed_out=false
  local chunk_expired=false
  [ -f "${result_file}.timeout" ] && timed_out=true
  [ -f "${result_file}.chunk_expire" ] && chunk_expired=true

  # Clean up temp files (keep raw_stream_file on failure for debugging)
  rm -f "$result_file" "${result_file}.timeout" "${result_file}.chunk_expire" "$heartbeat_file" "$claude_pid_file"

  # Calculate duration
  local end_time duration_secs duration_str
  end_time=$(date +%s)
  duration_secs=$(( end_time - start_time ))
  duration_str=$(format_duration "$duration_secs")

  # Check for chunk expiry — not a failure, create continuation task
  if $chunk_expired; then
    log "CHUNK_DONE: ${task_id} — chunk ${chunk} completed in ${duration_str}. Partial output preserved."

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local next_chunk=$(( chunk + 1 ))

    # Capture partial progress — if result_text is empty (killed mid-tool-use),
    # build progress from tool activity log so the next chunk knows what happened
    local progress_summary="${result_text:0:2000}"
    if [ -z "$progress_summary" ] || [[ "$progress_summary" == "(No text output"* ]]; then
      local tool_log
      tool_log=$(sqlite3 "$LEDGER_DB" "SELECT payload_json FROM events WHERE task_id='${task_id}' AND event_type='tool_use' ORDER BY rowid;" 2>/dev/null | jq -r '.tool' 2>/dev/null | paste -sd', ' || echo "")
      progress_summary="Chunk ${chunk} used ${tool_count} tools (${tool_log}) in ${duration_str} but was stopped before producing text output. The work may have made file changes — check the files listed in the task description."
    fi

    # Write result for this chunk (informational — not a failure)
    jq -n \
      --arg id "${task_id}-result" \
      --arg taskId "$task_id" \
      --arg created "$now" \
      --arg from "reactor" \
      --arg duration "$duration_str" \
      --arg summary "Chunk ${chunk} completed (wall-clock limit). Continuation queued as chunk ${next_chunk}." \
      --arg progress "$progress_summary" \
      '{id: $id, taskId: $taskId, created: $created, from: $from, status: "chunked", duration: $duration, summary: $summary, partial_progress: $progress}' \
      > "${OUTBOX}/${task_id}-result.json"

    mv "$taskfile" "${OUTBOX}/${task_id}-task.json"
    emit_event "$task_id" "$subject" "chunked" "$duration_str" "$channel_id"
    ledger_job_finished "$task_id" "chunked" "$now" "$duration_secs" "0" "$tool_count" "Chunk ${chunk} complete, continuing as chunk ${next_chunk}"
    ledger_event "$task_id" "chunked" "$now" "{\"chunk\":${chunk},\"next_chunk\":${next_chunk}}"

    # Create continuation task in inbox
    local cont_id="${original_task_id}-c${next_chunk}"
    jq -n \
      --arg id "$cont_id" \
      --arg subject "$subject" \
      --arg description "$description" \
      --arg to "$to" \
      --arg priority "$priority" \
      --arg channelId "$channel_id" \
      --arg originalTaskId "$original_task_id" \
      --argjson chunk "$next_chunk" \
      --arg prior_progress "$progress_summary" \
      --arg status "pending" \
      '{id: $id, subject: $subject, description: $description, to: $to, priority: $priority, channelId: $channelId, original_task_id: $originalTaskId, chunk: $chunk, prior_progress: $prior_progress, status: $status}' \
      > "${INBOX}/${cont_id}.json"

    log "CONTINUATION: Created ${cont_id} (chunk ${next_chunk}/${MAX_CHUNKS})"
    local time_used=$(( chunk * effective_chunk_wall / 60 ))
    local time_remaining=$(( (MAX_CHUNKS - chunk) * effective_chunk_wall / 60 ))
    discord_embed ">> Reactor: ${subject}" "$(printf '**Chunk %d/%d done** (%s)\n**Time used:** ~%dmin / ~%dmin budget\n\n**Progress so far:**\n%s...\n\nContinuing as chunk %d. To redirect or stop, delete `%s` from inbox.' "$chunk" "$MAX_CHUNKS" "$duration_str" "$time_used" "$(( MAX_CHUNKS * effective_chunk_wall / 60 ))" "${progress_summary:0:300}" "$next_chunk" "${cont_id}.json")"

    rm -f "$raw_stream_file"
    _REACTOR_ACTIVE_TASKFILE=""
    on_task_success  # chunk completion is a success, not a failure
    return 0
  fi

  # Check for timeout
  if $timed_out; then
    log "FAIL: ${task_id} — timed out after ${duration_str} of inactivity"

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
      --arg id "${task_id}-result" \
      --arg taskId "$task_id" \
      --arg created "$now" \
      --arg from "reactor" \
      --arg duration "$duration_str" \
      --arg reason "Timed out: no output for ${INACTIVITY_TIMEOUT}s. Partial output: ${result_text:0:500}" \
      '{id: $id, taskId: $taskId, created: $created, from: $from, status: "failed", duration: $duration, reason: $reason, relay_handoff_required: true}' \
      > "${OUTBOX}/${task_id}-result.json"

    mv "$taskfile" "${OUTBOX}/${task_id}-task.json"
    emit_event "$task_id" "$subject" "fail" "$duration_str" "$channel_id"
    local timeout_ts
    timeout_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ledger_job_finished "$task_id" "timeout" "$timeout_ts" "$duration_secs" "" "$tool_count" "Timed out: no output for ${INACTIVITY_TIMEOUT}s"
    ledger_event "$task_id" "timeout" "$timeout_ts" '{"relay_handoff_required":true}'
    ledger_populate_from_result "$task_id" "$result_text" "$timeout_ts"
    emit_handoff_artifact "$task_id" "timeout" "$subject" "$duration_str" "relay-notify-failure" "Timed out: no output for ${INACTIVITY_TIMEOUT}s" "$channel_id"
    discord_embed "X Reactor: ${subject}" "$(printf '**Status:** Timed out (no output for 10min)\n**Duration:** %s' "$duration_str")"

    # Clear active task tracker
    _REACTOR_ACTIVE_TASKFILE=""
    on_task_fail
    return 1
  fi

  # Check for non-zero exit
  if [ "$exit_code" -ne 0 ]; then
    log "FAIL: ${task_id} — claude exited with code ${exit_code} after ${duration_str}"

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq -n \
      --arg id "${task_id}-result" \
      --arg taskId "$task_id" \
      --arg created "$now" \
      --arg from "reactor" \
      --arg duration "$duration_str" \
      --arg reason "Claude Code exited with code ${exit_code}: ${result_text:0:500}" \
      '{id: $id, taskId: $taskId, created: $created, from: $from, status: "failed", duration: $duration, reason: $reason, relay_handoff_required: true}' \
      > "${OUTBOX}/${task_id}-result.json"

    mv "$taskfile" "${OUTBOX}/${task_id}-task.json"
    emit_event "$task_id" "$subject" "fail" "$duration_str" "$channel_id"
    local fail_ts
    fail_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ledger_job_finished "$task_id" "failed" "$fail_ts" "$duration_secs" "$exit_code" "$tool_count" "${result_text:0:500}"
    ledger_event "$task_id" "fail" "$fail_ts" "{\"exit_code\":$exit_code,\"relay_handoff_required\":true}"
    ledger_populate_from_result "$task_id" "$result_text" "$fail_ts"
    emit_handoff_artifact "$task_id" "failed" "$subject" "$duration_str" "relay-notify-failure" "Exit code ${exit_code}: ${result_text:0:300}" "$channel_id"
    discord_embed "X Reactor: ${subject}" "$(printf '**Status:** Failed (exit code %s)\n**Duration:** %s\n**Error:** %s' "$exit_code" "$duration_str" "${result_text:0:300}")"

    # Clear active task tracker
    _REACTOR_ACTIVE_TASKFILE=""
    on_task_fail
    return 1
  fi

  # === Success: write result to outbox (Bug 3: with Discord notification) ===
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Extract first line as summary preview
  local summary_preview
  summary_preview=$(echo "$result_text" | head -c 300)

  jq -n \
    --arg id "${task_id}-result" \
    --arg taskId "$task_id" \
    --arg created "$now" \
    --arg from "reactor" \
    --arg duration "$duration_str" \
    --arg summary "$result_text" \
    '{id: $id, taskId: $taskId, created: $created, from: $from, status: "completed", duration: $duration, summary: $summary, relay_handoff_required: true}' \
    > "${OUTBOX}/${task_id}-result.json"

  mv "$taskfile" "${OUTBOX}/${task_id}-task.json"
  log "DONE: ${task_id} — completed in ${duration_str}, result written to outbox"
  emit_event "$task_id" "$subject" "done" "$duration_str" "$channel_id"
  ledger_job_finished "$task_id" "completed" "$now" "$duration_secs" "0" "$tool_count" "${result_text:0:500}"
  ledger_event "$task_id" "done" "$now" '{"relay_handoff_required":true}'

  # Auto-populate retros, questions, feedback from result text
  ledger_populate_from_result "$task_id" "$result_text" "$now"

  # Emit handoff artifact for Relay human-facing delivery
  emit_handoff_artifact "$task_id" "completed" "$subject" "$duration_str" "relay-notify" "$summary_preview" "$channel_id"

  # Clean up raw stream on success (not needed for debugging)
  rm -f "$raw_stream_file"

  # Post completion embed to Discord
  discord_embed "OK Reactor: ${subject}" "$(printf '**Status:** Completed\n**Duration:** %s\n**Preview:** %s...' "$duration_str" "$summary_preview")"

  # Clear active task tracker
  _REACTOR_ACTIVE_TASKFILE=""
  on_task_success
}

# Rate-limit backoff helpers
check_backoff() {
  if [ -f "$BACKOFF_FILE" ]; then
    local resume_at
    resume_at=$(cat "$BACKOFF_FILE" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    if [ "$now" -lt "$resume_at" ]; then
      local wait_secs=$(( resume_at - now ))
      log "BACKOFF: Rate-limit cooldown active. Resuming in ${wait_secs}s."
      return 1  # still in backoff
    else
      rm -f "$BACKOFF_FILE"
      CONSECUTIVE_FAILS=0
      # Enter limp mode — shorter chunks until confidence returns
      touch "$LIMP_MODE_FILE"
      CONSECUTIVE_SUCCESSES=0
      log "BACKOFF: Cooldown expired. Entering limp mode (${CHUNK_MIN_WALL}s chunks until ${RAMP_UP_THRESHOLD} consecutive successes)."
      discord_embed ">> Reactor: Limp Mode" "$(printf 'Rate-limit cooldown cleared.\n**Chunk size:** %ds (reduced from %ds)\n**Full power after:** %d consecutive successes' "$CHUNK_MIN_WALL" "$CHUNK_MAX_WALL" "$RAMP_UP_THRESHOLD")"
    fi
  fi
  return 0
}

enter_backoff() {
  local backoff_secs=$(( BACKOFF_BASE * (2 ** (CONSECUTIVE_FAILS - MAX_CONSECUTIVE_FAILS)) ))
  [ "$backoff_secs" -gt "$BACKOFF_MAX" ] && backoff_secs=$BACKOFF_MAX
  local resume_at=$(( $(date +%s) + backoff_secs ))
  echo "$resume_at" > "$BACKOFF_FILE"
  log "BACKOFF: ${CONSECUTIVE_FAILS} consecutive failures. Pausing for ${backoff_secs}s ($(date -d "@$resume_at" +%H:%M:%S 2>/dev/null || echo "~$(( backoff_secs / 60 ))m"))."
  discord_embed "Pause Reactor: Rate Limit" "$(printf '**Consecutive failures:** %d\n**Pausing:** %ds\n**Resumes:** %s\nPending tasks will wait. No work is lost.' "$CONSECUTIVE_FAILS" "$backoff_secs" "$(date -d "@$resume_at" +%H:%M:%S 2>/dev/null || echo "~$(( backoff_secs / 60 ))m")")"
}

# Get effective chunk duration (respects limp mode)
get_chunk_wall() {
  if [ -f "$LIMP_MODE_FILE" ]; then
    echo "$CHUNK_MIN_WALL"
  else
    echo "$CHUNK_MAX_WALL"
  fi
}

on_task_success() {
  CONSECUTIVE_FAILS=0
  rm -f "$BACKOFF_FILE"
  # Limp mode ramp-up: exit after enough consecutive successes
  if [ -f "$LIMP_MODE_FILE" ]; then
    CONSECUTIVE_SUCCESSES=$(( CONSECUTIVE_SUCCESSES + 1 ))
    if [ "$CONSECUTIVE_SUCCESSES" -ge "$RAMP_UP_THRESHOLD" ]; then
      rm -f "$LIMP_MODE_FILE"
      log "LIMP_MODE: Exiting — ${CONSECUTIVE_SUCCESSES} consecutive successes. Full chunk size restored (${CHUNK_MAX_WALL}s)."
      discord_embed "OK Reactor: Full Power" "$(printf '**%d consecutive successes** — limp mode cleared.\n**Chunk size:** %ds (restored)' "$CONSECUTIVE_SUCCESSES" "$CHUNK_MAX_WALL")"
      CONSECUTIVE_SUCCESSES=0
    else
      log "LIMP_MODE: ${CONSECUTIVE_SUCCESSES}/${RAMP_UP_THRESHOLD} successes toward full power."
    fi
  else
    CONSECUTIVE_SUCCESSES=0
  fi
}

on_task_fail() {
  CONSECUTIVE_FAILS=$(( CONSECUTIVE_FAILS + 1 ))
  CONSECUTIVE_SUCCESSES=0  # Reset ramp-up on any failure
  if [ "$CONSECUTIVE_FAILS" -ge "$MAX_CONSECUTIVE_FAILS" ]; then
    enter_backoff
  fi
}

# Main loop
log "Reactor online. Polling ${INBOX} every ${POLL_INTERVAL}s."

run_once=false
[ "${1:-}" = "--once" ] && run_once=true

while true; do
  # Check if we're in a backoff cooldown
  if ! check_backoff; then
    sleep "$POLL_INTERVAL"
    continue
  fi

  for f in "$INBOX"/*.json; do
    [ -f "$f" ] || continue

    # Re-check backoff before each task (might have entered mid-batch)
    if ! check_backoff; then
      break
    fi

    process_task "$f" || true

    # === Reliability guard: catch stuck in-progress tasks ===
    # Only fires if process_task actually claimed this task (set _REACTOR_ACTIVE_TASKFILE)
    # but crashed before reaching any of its cleanup paths.
    # Tasks already in-progress from a previous reactor run are left untouched.
    if [ "$_REACTOR_ACTIVE_TASKFILE" = "$f" ] && [ -f "$f" ]; then
      stuck_status=$(jq -r '.status' "$f" 2>/dev/null || echo "")
      if [ "$stuck_status" = "in-progress" ]; then
        force_fail_task "$f" "$_REACTOR_ACTIVE_TASKID" "$_REACTOR_ACTIVE_SUBJECT" "$_REACTOR_START_TIME" "process_task exited unexpectedly without completing cleanup"
        _REACTOR_ACTIVE_TASKFILE=""
      fi
    fi
  done

  if $run_once; then
    log "Single pass complete (--once mode)."
    break
  fi

  sleep "$POLL_INTERVAL"
done
