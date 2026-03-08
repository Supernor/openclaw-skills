#!/usr/bin/env bash
# youtube-ingest.sh — Ingest YouTube transcripts via Gemini API
# Called by Research agent's /youtube-ingest skill
# Intent: Informed [I18]
set -eo pipefail

DB="/root/.openclaw/transcripts.db"
SCRIPT="/root/.openclaw/scripts/youtube-ingest.py"

# Ensure DB exists
python3 "$SCRIPT" --init-db 2>/dev/null

# Pass all args to Python handler
python3 "$SCRIPT" "$@"
