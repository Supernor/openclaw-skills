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
#
# Usage:
#   bridge-reactor.sh              # foreground
#   bridge-reactor.sh --once       # process one batch and exit (for testing)

set -eo pipefail

BASE="/root/.openclaw"
BRIDGE="${BASE}/bridge"
INBOX="${BRIDGE}/inbox"
OUTBOX="${BRIDGE}/outbox"
BRIDGE_SH="${BASE}/scripts/bridge.sh"
REACTOR_POST="${BASE}/scripts/reactor-post.sh"
LOGFILE="${BASE}/logs/reactor.log"
POLL_INTERVAL=10
INACTIVITY_TIMEOUT=600  # 10 minutes of no output = stuck

mkdir -p "$INBOX" "$OUTBOX" "$(dirname "$LOGFILE")"

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

process_task() {
  local taskfile="$1"
  local task_id subject description to priority files_json status

  task_id=$(jq -r '.id' "$taskfile")
  subject=$(jq -r '.subject' "$taskfile")
  description=$(jq -r '.description // ""' "$taskfile")
  to=$(jq -r '.to' "$taskfile")
  priority=$(jq -r '.priority // "normal"' "$taskfile")
  files_json=$(jq -r '.files // [] | join(", ")' "$taskfile")
  status=$(jq -r '.status' "$taskfile")

  # Only process pending tasks
  if [ "$status" != "pending" ]; then
    return 0
  fi

  log "PICKUP: ${task_id} — ${subject} (for: ${to}, priority: ${priority})"

  # Mark as in-progress
  jq '.status = "in-progress"' "$taskfile" > "${taskfile}.tmp" && mv "${taskfile}.tmp" "$taskfile"

  # Notify Discord: task started
  discord_embed "Reactor: ${subject}" "Task picked up. Working..."

  # Record start time
  local start_time
  start_time=$(date +%s)

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

## Response
Be concise. Return actionable results the agent can relay to the user.
If you create or modify files, list the paths and a one-line summary of each change."

  # === Run Claude Code with monitored execution ===
  # Uses --output-format stream-json for structured progress events.
  # Parses tool_use events → posts tool names to Discord as progress.
  # Accumulates text_delta events → builds final result text.
  # Watchdog kills claude if no output for INACTIVITY_TIMEOUT seconds.

  local raw_stream_file result_file heartbeat_file claude_pid_file
  raw_stream_file=$(mktemp /tmp/reactor-stream.XXXXXX)
  result_file=$(mktemp /tmp/reactor-result.XXXXXX)
  heartbeat_file=$(mktemp /tmp/reactor-heartbeat.XXXXXX)
  claude_pid_file=$(mktemp /tmp/reactor-claude-pid.XXXXXX)
  touch "$heartbeat_file"
  local tool_count=0

  log "RUNNING claude -p for task ${task_id}..."

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
            discord_post "⚙️ ${subject} — using ${tn} (#${tool_count})" &
            log "  TOOL: ${task_id} — ${tn} (#${tool_count})"
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

  # Background watchdog: kill if heartbeat goes stale
  (
    while kill -0 "$pipe_pid" 2>/dev/null; do
      local last_beat now_epoch idle
      last_beat=$(stat -c %Y "$heartbeat_file" 2>/dev/null || echo 0)
      now_epoch=$(date +%s)
      idle=$(( now_epoch - last_beat ))

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

  # Check for timeout
  local timed_out=false
  [ -f "${result_file}.timeout" ] && timed_out=true

  # Clean up temp files (keep raw_stream_file on failure for debugging)
  rm -f "$result_file" "${result_file}.timeout" "$heartbeat_file" "$claude_pid_file"

  # Calculate duration
  local end_time duration_secs duration_str
  end_time=$(date +%s)
  duration_secs=$(( end_time - start_time ))
  duration_str=$(format_duration "$duration_secs")

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
      '{id: $id, taskId: $taskId, created: $created, from: $from, status: "failed", duration: $duration, reason: $reason}' \
      > "${OUTBOX}/${task_id}-result.json"

    mv "$taskfile" "${OUTBOX}/${task_id}-task.json"
    discord_embed "❌ Reactor: ${subject}" "$(printf '**Status:** Timed out (no output for 10min)\n**Duration:** %s' "$duration_str")"
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
      '{id: $id, taskId: $taskId, created: $created, from: $from, status: "failed", duration: $duration, reason: $reason}' \
      > "${OUTBOX}/${task_id}-result.json"

    mv "$taskfile" "${OUTBOX}/${task_id}-task.json"
    discord_embed "❌ Reactor: ${subject}" "$(printf '**Status:** Failed (exit code %s)\n**Duration:** %s\n**Error:** %s' "$exit_code" "$duration_str" "${result_text:0:300}")"
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
    '{id: $id, taskId: $taskId, created: $created, from: $from, status: "completed", duration: $duration, summary: $summary}' \
    > "${OUTBOX}/${task_id}-result.json"

  mv "$taskfile" "${OUTBOX}/${task_id}-task.json"
  log "DONE: ${task_id} — completed in ${duration_str}, result written to outbox"

  # Clean up raw stream on success (not needed for debugging)
  rm -f "$raw_stream_file"

  # Post completion embed to Discord
  discord_embed "✅ Reactor: ${subject}" "$(printf '**Status:** Completed\n**Duration:** %s\n**Preview:** %s...' "$duration_str" "$summary_preview")"
}

# Main loop
log "Reactor online. Polling ${INBOX} every ${POLL_INTERVAL}s."

run_once=false
[ "${1:-}" = "--once" ] && run_once=true

while true; do
  for f in "$INBOX"/*.json; do
    [ -f "$f" ] || continue
    process_task "$f" || true
  done

  if $run_once; then
    log "Single pass complete (--once mode)."
    break
  fi

  sleep "$POLL_INTERVAL"
done
