#!/usr/bin/env bash
# reactor-status.sh — Unified Reactor health status as JSON
# Works from host OR container. Graceful fallbacks for every field.
#
# Usage:   reactor-status.sh          # JSON to stdout
#          reactor-status.sh --pretty  # Pretty-printed JSON
#
# Output schema:
# {
#   "reactor": "online|offline",
#   "version": "<claude-version-or-null>",
#   "service": "active|inactive|unknown",
#   "bridge": {"pending": N, "inProgress": N, "completed": N},
#   "sourceOfTruth": "bridge.sh|ledger|file-count",
#   "lastCompleted": "<iso-or-null>",
#   "uptime": "<human-or-null>",
#   "timestamp": "<iso>",
#   "notes": [...]
# }

set -eo pipefail

PRETTY=""
[ "${1:-}" = "--pretty" ] && PRETTY=1

# ── Locate base path (host or container) ──
BASE="/root/.openclaw"
if [ ! -d "$BASE" ] && [ -d "/home/node/.openclaw" ]; then
  BASE="/home/node/.openclaw"
fi

LEDGER_DB="${BASE}/bridge/reactor-ledger.sqlite"
NOTES=()

# ── Helper: add a note ──
note() { NOTES+=("$1"); }

# ── 1. Reactor online check ──
# Check if the bridge-reactor watcher process is running (host) or if the
# service file reports active (host). From container, infer from recent
# bridge activity.
REACTOR="offline"
VERSION="null"
SERVICE="unknown"

# Try systemctl (host only)
if command -v systemctl &>/dev/null; then
  ACTIVE_STATE=$(systemctl show openclaw-reactor --property=ActiveState 2>/dev/null | cut -d= -f2)
  case "$ACTIVE_STATE" in
    active)   SERVICE="active";   REACTOR="online" ;;
    inactive) SERVICE="inactive"; REACTOR="offline" ;;
    failed)   SERVICE="failed";   REACTOR="offline"; note "systemd service in failed state" ;;
    *)        SERVICE="unknown" ;;
  esac
else
  # Inside container — check if a job was completed in the last 30 minutes
  if [ -f "$LEDGER_DB" ] && command -v sqlite3 &>/dev/null; then
    RECENT=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM jobs WHERE status IN ('completed','in-progress') AND REPLACE(REPLACE(date_received, 'T', ' '), 'Z', '') > datetime('now', '-30 minutes');" 2>/dev/null || echo "0")
    if [ "$RECENT" -gt 0 ] 2>/dev/null; then
      REACTOR="online"
      note "inferred online from recent bridge activity (no systemctl access)"
    else
      REACTOR="offline"
      note "no recent bridge activity (no systemctl access — may be false negative)"
    fi
  else
    note "cannot determine reactor state (no systemctl, no ledger)"
  fi
fi

# Try claude --version (host only — binary not in container)
if command -v claude &>/dev/null; then
  RAW_VERSION=$(claude --version 2>/dev/null || true)
  if [ -n "$RAW_VERSION" ]; then
    VERSION=$(printf '%s' "$RAW_VERSION" | head -1)
  fi
fi

# ── 2. Bridge stats — bridge.sh status is primary source of truth ──
PENDING=0
IN_PROGRESS=0
COMPLETED=0
LAST_COMPLETED="null"
SOURCE_OF_TRUTH="unknown"

BRIDGE_SH="${BASE}/scripts/bridge.sh"
BRIDGE_OK=false

# Primary: try bridge.sh status (live file-based counts)
if [ -x "$BRIDGE_SH" ]; then
  BRIDGE_JSON=$("$BRIDGE_SH" status 2>/dev/null) || BRIDGE_JSON=""
  if [ -n "$BRIDGE_JSON" ] && echo "$BRIDGE_JSON" | jq -e '.summary' &>/dev/null; then
    PENDING=$(echo "$BRIDGE_JSON" | jq -r '.summary.pending // 0')
    IN_PROGRESS=$(echo "$BRIDGE_JSON" | jq -r '.summary.inProgress // 0')
    COMPLETED=$(echo "$BRIDGE_JSON" | jq -r '.summary.completed // 0')
    SOURCE_OF_TRUTH="bridge.sh"
    BRIDGE_OK=true
  fi
fi

# Fallback: ledger DB
if [ "$BRIDGE_OK" = false ]; then
  if [ -f "$LEDGER_DB" ] && command -v sqlite3 &>/dev/null; then
    PENDING=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM jobs WHERE status='pending';" 2>/dev/null || echo "0")
    IN_PROGRESS=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM jobs WHERE status='in-progress';" 2>/dev/null || echo "0")
    COMPLETED=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM jobs WHERE status='completed';" 2>/dev/null || echo "0")
    SOURCE_OF_TRUTH="ledger"
    note "bridge.sh unavailable — using ledger as fallback (counts may diverge from live state)"
  else
    note "ledger DB not found at ${LEDGER_DB}"
    # Last resort: count files directly
    INBOX_DIR="${BASE}/bridge/inbox"
    OUTBOX_DIR="${BASE}/bridge/outbox"
    if [ -d "$INBOX_DIR" ]; then
      PENDING=$(find "$INBOX_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)
    fi
    if [ -d "$OUTBOX_DIR" ]; then
      COMPLETED=$(find "$OUTBOX_DIR" -maxdepth 1 -name '*-result.json' 2>/dev/null | wc -l)
    fi
    SOURCE_OF_TRUTH="file-count"
    note "no bridge.sh or ledger — using raw file counts as last resort"
  fi
fi

# Last completed timestamp (always from ledger when available)
if [ -f "$LEDGER_DB" ] && command -v sqlite3 &>/dev/null; then
  RAW_LAST=$(sqlite3 "$LEDGER_DB" "SELECT date_finished FROM jobs WHERE status='completed' ORDER BY date_finished DESC LIMIT 1;" 2>/dev/null || true)
  if [ -n "$RAW_LAST" ]; then
    LAST_COMPLETED="$RAW_LAST"
  fi
fi

# ── 3. Uptime ──
UPTIME="null"
if command -v systemctl &>/dev/null; then
  RAW_UPTIME=$(systemctl show openclaw-reactor --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)
  if [ -n "$RAW_UPTIME" ] && [ "$RAW_UPTIME" != "" ]; then
    # Calculate human-readable uptime from ActiveEnterTimestamp
    START_EPOCH=$(date -d "$RAW_UPTIME" +%s 2>/dev/null || echo "")
    if [ -n "$START_EPOCH" ]; then
      NOW_EPOCH=$(date +%s)
      DIFF=$((NOW_EPOCH - START_EPOCH))
      DAYS=$((DIFF / 86400))
      HOURS=$(( (DIFF % 86400) / 3600 ))
      MINS=$(( (DIFF % 3600) / 60 ))
      if [ "$DAYS" -gt 0 ]; then
        UPTIME="${DAYS}d ${HOURS}h ${MINS}m"
      elif [ "$HOURS" -gt 0 ]; then
        UPTIME="${HOURS}h ${MINS}m"
      else
        UPTIME="${MINS}m"
      fi
    fi
  fi
fi

# ── 4. Timestamp ──
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── Build JSON ──
# Use jq for safe JSON construction
NOTES_JSON="[]"
if [ ${#NOTES[@]} -gt 0 ]; then
  NOTES_JSON=$(printf '%s\n' "${NOTES[@]}" | jq -R . | jq -s .)
fi

JQ_FILTER='
{
  reactor: $reactor,
  version: (if $version == "null" then null else $version end),
  service: $service,
  bridge: {
    pending: ($pending | tonumber),
    inProgress: ($in_progress | tonumber),
    completed: ($completed | tonumber)
  },
  sourceOfTruth: $sot,
  lastCompleted: (if $last == "null" then null else $last end),
  uptime: (if $uptime == "null" then null else $uptime end),
  timestamp: $timestamp,
  notes: $notes
}'

OUTPUT=$(jq -n \
  --arg reactor "$REACTOR" \
  --arg version "$VERSION" \
  --arg service "$SERVICE" \
  --arg pending "$PENDING" \
  --arg in_progress "$IN_PROGRESS" \
  --arg completed "$COMPLETED" \
  --arg sot "$SOURCE_OF_TRUTH" \
  --arg last "$LAST_COMPLETED" \
  --arg uptime "$UPTIME" \
  --arg timestamp "$TIMESTAMP" \
  --argjson notes "$NOTES_JSON" \
  "$JQ_FILTER")

if [ -n "$PRETTY" ]; then
  echo "$OUTPUT" | jq .
else
  echo "$OUTPUT"
fi
