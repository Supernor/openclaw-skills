#!/usr/bin/env bash
# Pre-compact checkpoint — triggered by Claude Code PreCompact hook
# Appends a compaction marker to the reactor journal so post-compact
# context recovery knows compaction happened.
set -euo pipefail

JOURNAL="/root/.openclaw/reactor-journal.md"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Read context stats if available
CTX_PCT="unknown"
if [ -f /tmp/claude-context.json ]; then
  CTX_PCT=$(jq -r '.used_pct // "unknown"' /tmp/claude-context.json 2>/dev/null || echo "unknown")
fi

# Append compaction marker to journal
if [ -f "$JOURNAL" ]; then
  echo "" >> "$JOURNAL"
  echo "## COMPACTION @ ${TIMESTAMP} (ctx: ${CTX_PCT}%)" >> "$JOURNAL"
  echo "<!-- Read this file after compaction to recover session state -->" >> "$JOURNAL"
fi
