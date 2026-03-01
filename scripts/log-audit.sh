#!/bin/bash
# log-audit.sh — Audit all OpenClaw log sources: persistence, retention, size, health
# Outputs structured JSON. Run nightly via cron.
set -eo pipefail

OPENCLAW_DIR="/home/node/.openclaw"
GATEWAY_LOG_DIR="/tmp/openclaw"
PERSISTENT_LOG_DIR="$OPENCLAW_DIR/logs/gateway"
SESSIONS_DIR="$OPENCLAW_DIR/agents"
CONFIG_AUDIT="$OPENCLAW_DIR/logs/config-audit.jsonl"
CRON_RUNS_DIR="$OPENCLAW_DIR/cron/runs"
DELIVERY_QUEUE="$OPENCLAW_DIR/delivery-queue"
DELIVERY_FAILED="$DELIVERY_QUEUE/failed"
MODEL_HEALTH_NOTIF="$OPENCLAW_DIR/model-health-notifications.jsonl"
REPOMAN_LOG="$OPENCLAW_DIR/workspace-spec-github/logs/repo-man.log"

NOW=$(date +%s)
TODAY=$(date +%Y-%m-%d)
SEVEN_DAYS=$((7 * 86400))
MAX_SESSION_AGE_DAYS=7
MAX_SESSION_SIZE_MB=50
MAX_CONFIG_AUDIT_LINES=1000
MAX_GATEWAY_LOG_DAYS=7
MAX_REPOMAN_LOG_LINES=500

WARNINGS=()
ACTIONS=()

# --- 1. Gateway log: persist from /tmp, prune old ---
gateway_status="ok"
gateway_today_size=0
gateway_persisted=0
gateway_pruned=0

mkdir -p "$PERSISTENT_LOG_DIR"

# Copy today's log to persistent location
if [ -f "$GATEWAY_LOG_DIR/openclaw-$TODAY.log" ]; then
  cp "$GATEWAY_LOG_DIR/openclaw-$TODAY.log" "$PERSISTENT_LOG_DIR/openclaw-$TODAY.log"
  gateway_today_size=$(stat -c%s "$GATEWAY_LOG_DIR/openclaw-$TODAY.log" 2>/dev/null || echo 0)
  gateway_persisted=1
fi

# Also persist any other days in /tmp that aren't yet saved
for f in "$GATEWAY_LOG_DIR"/openclaw-*.log; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  if [ ! -f "$PERSISTENT_LOG_DIR/$fname" ]; then
    cp "$f" "$PERSISTENT_LOG_DIR/$fname"
    gateway_persisted=$((gateway_persisted + 1))
  fi
done

# Prune persistent logs older than MAX_GATEWAY_LOG_DAYS
for f in "$PERSISTENT_LOG_DIR"/openclaw-*.log; do
  [ -f "$f" ] || continue
  file_age=$(( NOW - $(stat -c%Y "$f") ))
  if [ "$file_age" -gt $((MAX_GATEWAY_LOG_DAYS * 86400)) ]; then
    rm "$f"
    gateway_pruned=$((gateway_pruned + 1))
  fi
done

persistent_count=$(find "$PERSISTENT_LOG_DIR" -name "openclaw-*.log" 2>/dev/null | wc -l)
persistent_size=$(du -sb "$PERSISTENT_LOG_DIR" 2>/dev/null | cut -f1)

if [ "$gateway_today_size" -eq 0 ]; then
  gateway_status="warning"
  WARNINGS+=("No gateway log for today ($TODAY)")
fi

# --- 2. Session files: inventory per agent, prune old ---
session_total_size=0
session_total_files=0
session_pruned=0
AGENT_SESSIONS="["
agent_first=true

for agent_dir in "$SESSIONS_DIR"/*/; do
  [ -d "$agent_dir/sessions" ] || continue
  agent_id=$(basename "$agent_dir")

  agent_files=0
  agent_size=0
  agent_pruned_count=0
  agent_kept_files=()

  for sf in "$agent_dir/sessions/"*.jsonl; do
    [ -f "$sf" ] || continue
    file_age=$(( NOW - $(stat -c%Y "$sf") ))
    file_size=$(stat -c%s "$sf" 2>/dev/null || echo 0)

    if [ "$file_age" -gt $((MAX_SESSION_AGE_DAYS * 86400)) ]; then
      # Keep at least 3 most recent per agent even if old
      agent_kept_files+=("$file_age:$sf:$file_size")
    else
      agent_files=$((agent_files + 1))
      agent_size=$((agent_size + file_size))
    fi
  done

  # Sort old files by age (newest first), keep first 3, prune rest
  if [ ${#agent_kept_files[@]} -gt 0 ]; then
    IFS=$'\n' sorted=($(printf '%s\n' "${agent_kept_files[@]}" | sort -t: -k1 -n)); unset IFS
    kept=0
    for entry in "${sorted[@]}"; do
      sf=$(echo "$entry" | cut -d: -f2)
      fs=$(echo "$entry" | cut -d: -f3)
      if [ $kept -lt 3 ]; then
        agent_files=$((agent_files + 1))
        agent_size=$((agent_size + fs))
        kept=$((kept + 1))
      else
        rm "$sf"
        agent_pruned_count=$((agent_pruned_count + 1))
        session_pruned=$((session_pruned + 1))
      fi
    done
  fi

  session_total_files=$((session_total_files + agent_files))
  session_total_size=$((session_total_size + agent_size))

  agent_size_mb=$(awk "BEGIN{printf \"%.1f\", $agent_size/1048576}")
  if [ "$(awk "BEGIN{print ($agent_size > $MAX_SESSION_SIZE_MB * 1048576) ? 1 : 0}")" -eq 1 ]; then
    WARNINGS+=("Agent $agent_id sessions: ${agent_size_mb}MB exceeds ${MAX_SESSION_SIZE_MB}MB limit")
  fi

  if ! $agent_first; then AGENT_SESSIONS+=","; fi
  agent_first=false
  AGENT_SESSIONS+="{\"agent\":\"$agent_id\",\"files\":$agent_files,\"sizeBytes\":$agent_size,\"pruned\":$agent_pruned_count}"
done
AGENT_SESSIONS+="]"

# --- 3. Config audit log ---
config_audit_status="ok"
config_audit_lines=0
config_audit_rotated=false

if [ -f "$CONFIG_AUDIT" ]; then
  config_audit_lines=$(wc -l < "$CONFIG_AUDIT")
  if [ "$config_audit_lines" -gt "$MAX_CONFIG_AUDIT_LINES" ]; then
    # Rotate: keep last 500 lines
    tail -500 "$CONFIG_AUDIT" > "$CONFIG_AUDIT.tmp"
    mv "$CONFIG_AUDIT.tmp" "$CONFIG_AUDIT"
    config_audit_rotated=true
    config_audit_lines=500
    ACTIONS+=("Rotated config-audit.jsonl from $config_audit_lines to 500 lines")
  fi
  last_entry=$(tail -1 "$CONFIG_AUDIT" 2>/dev/null | jq -r '.timestamp // empty' 2>/dev/null || echo "unknown")
else
  config_audit_status="missing"
  last_entry="n/a"
  WARNINGS+=("config-audit.jsonl not found — config changes are untracked")
fi

# --- 4. Cron run health ---
cron_status="ok"
cron_failures=0
cron_total=0

if [ -d "$CRON_RUNS_DIR" ]; then
  for rf in "$CRON_RUNS_DIR"/*.jsonl; do
    [ -f "$rf" ] || continue
    # Check last 24h entries for errors
    while IFS= read -r line; do
      cron_total=$((cron_total + 1))
      status=$(echo "$line" | jq -r '.status // .lastStatus // empty' 2>/dev/null)
      if [ "$status" = "error" ] || [ "$status" = "failed" ]; then
        cron_failures=$((cron_failures + 1))
      fi
    done < <(tail -20 "$rf")
  done
  if [ "$cron_failures" -gt 0 ]; then
    cron_status="warning"
    WARNINGS+=("$cron_failures cron run failures in recent history")
  fi
else
  cron_status="no_runs_dir"
fi

# --- 5. Delivery queue ---
delivery_status="ok"
delivery_pending=0
delivery_failed=0

if [ -d "$DELIVERY_QUEUE" ]; then
  delivery_pending=$(find "$DELIVERY_QUEUE" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l)
fi
if [ -d "$DELIVERY_FAILED" ]; then
  delivery_failed=$(find "$DELIVERY_FAILED" -maxdepth 1 -name "*.json" 2>/dev/null | wc -l)
fi
if [ "$delivery_failed" -gt 0 ]; then
  delivery_status="warning"
  WARNINGS+=("$delivery_failed failed messages in delivery queue")
fi

# --- 6. Model health notifications ---
notif_status="ok"
notif_lines=0
if [ -f "$MODEL_HEALTH_NOTIF" ]; then
  notif_lines=$(wc -l < "$MODEL_HEALTH_NOTIF")
fi

# --- 7. Repo-Man log ---
repoman_status="ok"
repoman_lines=0
if [ -f "$REPOMAN_LOG" ]; then
  repoman_lines=$(wc -l < "$REPOMAN_LOG")
  if [ "$repoman_lines" -gt "$MAX_REPOMAN_LOG_LINES" ]; then
    tail -200 "$REPOMAN_LOG" > "$REPOMAN_LOG.tmp"
    mv "$REPOMAN_LOG.tmp" "$REPOMAN_LOG"
    repoman_lines=200
    ACTIONS+=("Rotated repo-man.log to 200 lines")
  fi
else
  repoman_status="empty"
fi

# --- 8. Disk summary ---
total_log_size=$(( ${persistent_size:-0} + session_total_size ))
total_log_size_mb=$(awk "BEGIN{printf \"%.1f\", $total_log_size/1048576}")

# --- Build JSON output ---
warning_json="["
wfirst=true
for w in "${WARNINGS[@]}"; do
  if ! $wfirst; then warning_json+=","; fi
  wfirst=false
  warning_json+="\"$(echo "$w" | sed 's/"/\\"/g')\""
done
warning_json+="]"

action_json="["
afirst=true
for a in "${ACTIONS[@]}"; do
  if ! $afirst; then action_json+=","; fi
  afirst=false
  action_json+="\"$(echo "$a" | sed 's/"/\\"/g')\""
done
action_json+="]"

if [ "${#WARNINGS[@]}" -gt 0 ]; then
  overall="warning"
else
  overall="ok"
fi

cat <<ENDJSON
{
  "status": "$overall",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "gatewayLog": {
    "status": "$gateway_status",
    "todaySizeBytes": $gateway_today_size,
    "persisted": $gateway_persisted,
    "pruned": $gateway_pruned,
    "persistentFiles": $persistent_count,
    "persistentSizeBytes": ${persistent_size:-0},
    "retentionDays": $MAX_GATEWAY_LOG_DAYS
  },
  "sessions": {
    "totalFiles": $session_total_files,
    "totalSizeBytes": $session_total_size,
    "pruned": $session_pruned,
    "retentionDays": $MAX_SESSION_AGE_DAYS,
    "minKeptPerAgent": 3,
    "agents": $AGENT_SESSIONS
  },
  "configAudit": {
    "status": "$config_audit_status",
    "lines": $config_audit_lines,
    "lastEntry": "$last_entry",
    "rotated": $config_audit_rotated,
    "maxLines": $MAX_CONFIG_AUDIT_LINES
  },
  "cronRuns": {
    "status": "$cron_status",
    "recentTotal": $cron_total,
    "recentFailures": $cron_failures
  },
  "deliveryQueue": {
    "status": "$delivery_status",
    "pending": $delivery_pending,
    "failed": $delivery_failed
  },
  "modelHealthNotifications": {
    "lines": $notif_lines
  },
  "repoManLog": {
    "status": "$repoman_status",
    "lines": $repoman_lines,
    "maxLines": $MAX_REPOMAN_LOG_LINES
  },
  "diskSummary": {
    "totalLogSizeMB": $total_log_size_mb,
    "gatewayPersistentMB": $(awk "BEGIN{printf \"%.1f\", ${persistent_size:-0}/1048576}"),
    "sessionsMB": $(awk "BEGIN{printf \"%.1f\", $session_total_size/1048576}")
  },
  "warnings": $warning_json,
  "actions": $action_json
}
ENDJSON
