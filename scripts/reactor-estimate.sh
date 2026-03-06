#!/usr/bin/env bash
# reactor-estimate.sh — Estimate task duration based on historical ledger data
# Usage: reactor-estimate.sh [keyword]
# Returns: average duration, chunk count, and confidence based on past similar tasks
#
# Examples:
#   reactor-estimate.sh                    # overall stats
#   reactor-estimate.sh "seed"             # tasks with "seed" in subject
#   reactor-estimate.sh "fix"              # tasks with "fix" in subject

BRIDGE="/root/.openclaw/bridge"
LEDGER_DB="${BRIDGE}/reactor-ledger.sqlite"

if [ ! -f "$LEDGER_DB" ]; then
  echo '{"error": "No ledger database found. No historical data yet."}'
  exit 1
fi

keyword="${1:-}"

# Overall stats
total=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM jobs;" 2>/dev/null || echo 0)
completed=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM jobs WHERE status='completed';" 2>/dev/null || echo 0)
failed=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM jobs WHERE status IN ('failed','timeout');" 2>/dev/null || echo 0)
chunked=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM jobs WHERE status='chunked';" 2>/dev/null || echo 0)

avg_duration=$(sqlite3 "$LEDGER_DB" "SELECT COALESCE(CAST(AVG(duration_seconds) AS INTEGER), 0) FROM jobs WHERE status='completed';" 2>/dev/null || echo 0)
max_duration=$(sqlite3 "$LEDGER_DB" "SELECT COALESCE(MAX(duration_seconds), 0) FROM jobs WHERE status='completed';" 2>/dev/null || echo 0)

# Format durations
format_dur() {
  local s=$1
  if [ "$s" -ge 60 ]; then
    echo "$(( s / 60 ))m$(( s % 60 ))s"
  else
    echo "${s}s"
  fi
}

# Current mode
if [ -f "${BRIDGE}/.reactor-limp-mode" ]; then
  mode="limp (2min chunks)"
elif [ -f "${BRIDGE}/.reactor-backoff" ]; then
  resume_at=$(cat "${BRIDGE}/.reactor-backoff" 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ "$now" -lt "$resume_at" ]; then
    mode="backoff (resumes in $(( resume_at - now ))s)"
  else
    mode="normal (5min chunks)"
  fi
else
  mode="normal (5min chunks)"
fi

echo "=== Reactor Estimate ==="
echo "Mode: ${mode}"
echo "Total tasks: ${total} (${completed} done, ${failed} failed, ${chunked} chunked)"
echo "Avg completion time: $(format_dur "$avg_duration")"
echo "Longest completion: $(format_dur "$max_duration")"

# Keyword-specific estimate
if [ -n "$keyword" ]; then
  echo ""
  echo "--- Tasks matching '${keyword}' ---"
  match_count=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM jobs WHERE subject LIKE '%${keyword}%';" 2>/dev/null || echo 0)
  match_avg=$(sqlite3 "$LEDGER_DB" "SELECT COALESCE(CAST(AVG(duration_seconds) AS INTEGER), 0) FROM jobs WHERE subject LIKE '%${keyword}%' AND status='completed';" 2>/dev/null || echo 0)
  match_success=$(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM jobs WHERE subject LIKE '%${keyword}%' AND status='completed';" 2>/dev/null || echo 0)

  if [ "$match_count" -eq 0 ]; then
    echo "No matching tasks found. Using overall average: ~$(format_dur "$avg_duration")"
    est_chunks=$(( (avg_duration + 299) / 300 ))
    [ "$est_chunks" -lt 1 ] && est_chunks=1
    echo "Estimated chunks: ${est_chunks} (~$(format_dur $(( est_chunks * 300 ))))"
  else
    echo "Found: ${match_count} (${match_success} completed)"
    echo "Avg time: $(format_dur "$match_avg")"
    est_chunks=$(( (match_avg + 299) / 300 ))
    [ "$est_chunks" -lt 1 ] && est_chunks=1
    echo "Estimated chunks: ${est_chunks} (~$(format_dur $(( est_chunks * 300 ))))"

    if [ "$match_count" -lt 3 ]; then
      echo "Confidence: Low (only ${match_count} samples)"
    elif [ "$match_count" -lt 10 ]; then
      echo "Confidence: Medium (${match_count} samples)"
    else
      echo "Confidence: High (${match_count} samples)"
    fi
  fi
fi

# Success rate
if [ "$total" -gt 0 ]; then
  success_pct=$(( completed * 100 / total ))
  echo ""
  echo "Success rate: ${success_pct}% (${completed}/${total})"
fi
