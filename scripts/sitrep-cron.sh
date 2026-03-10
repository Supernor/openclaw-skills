#!/usr/bin/env bash
# sitrep-cron.sh — Have Quartermaster refresh the sitrep every 30 min
# Intent: Efficient [I06]
set -eo pipefail

# Pre-compute satisfaction summary for injection
SAT_SUMMARY=$(/root/.openclaw/scripts/satisfaction-summary.sh 2>/dev/null || echo "Satisfaction: unavailable")

oc agent --agent spec-quartermaster \
  --message "Run sitrep. Use MCP tools: health, chart_count, chart_search for issues. Delegate to spec-strategy via agentToAgent for transcript/ideas data. Write result to /home/node/.openclaw/sitrep.md. Under 3000 chars. Focus on changes since last sitrep. Include this satisfaction line: ${SAT_SUMMARY}" \
  --timeout 180 2>&1 || echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) sitrep-cron: agent call failed" >> /root/.openclaw/logs/sitrep-cron.log
