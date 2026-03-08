#!/usr/bin/env bash
# transcript-auto-ingest.sh — Check for new @NateBJones videos and ingest
# Designed to run as a daily cron. Skips videos already in DB.
# Also triggers backfill for any videos missing summary/insights.
#
# Usage: transcript-auto-ingest.sh [@channel] [days]
# Default: @NateBJones, 7 days

set -eo pipefail

CHANNEL="${1:-@NateBJones}"
DAYS="${2:-7}"
LOGFILE="/root/.openclaw/logs/transcript-auto-ingest.log"
mkdir -p "$(dirname "$LOGFILE")"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOGFILE"; }

log "Starting auto-ingest: channel=$CHANNEL days=$DAYS"

# Step 1: Ingest new videos
log "Checking for new videos..."
python3 /root/.openclaw/scripts/youtube-ingest.py --channel "$CHANNEL" --days "$DAYS" 2>&1 | tee -a "$LOGFILE"

# Step 2: Backfill any missing summaries (limit 5 per run to control API cost)
NEEDS_BACKFILL=$(sqlite3 /root/.openclaw/transcripts.db \
  "SELECT COUNT(*) FROM videos WHERE (summary IS NULL OR summary = '') AND transcript IS NOT NULL AND length(transcript) > 200;")

if [ "$NEEDS_BACKFILL" -gt 0 ]; then
  log "Backfilling $NEEDS_BACKFILL videos via Strategist/Codex (max 5 this run)..."
  python3 /root/.openclaw/scripts/transcript-backfill.py --limit 5 2>&1 | tee -a "$LOGFILE"

  # Also refresh any missing description insights
  NEEDS_DESC=$(sqlite3 /root/.openclaw/transcripts.db \
    "SELECT COUNT(*) FROM videos WHERE summary IS NOT NULL AND summary <> '' AND (description_insights IS NULL OR description_insights = '');")
  if [ "$NEEDS_DESC" -gt 0 ]; then
    log "Refreshing $NEEDS_DESC description insights (max 5 this run)..."
    python3 /root/.openclaw/scripts/transcript-backfill.py --refresh-descriptions --limit 5 2>&1 | tee -a "$LOGFILE"
  fi
else
  log "All videos have summaries — no backfill needed."
fi

# Step 3: Report
TOTAL=$(sqlite3 /root/.openclaw/transcripts.db "SELECT COUNT(*) FROM videos;")
WITH_SUMMARY=$(sqlite3 /root/.openclaw/transcripts.db "SELECT COUNT(*) FROM videos WHERE summary IS NOT NULL AND summary <> '';")
LATEST=$(sqlite3 /root/.openclaw/transcripts.db "SELECT publish_date FROM videos ORDER BY publish_date DESC LIMIT 1;")

log "Done. Videos: $TOTAL (summaries: $WITH_SUMMARY). Latest: $LATEST"
