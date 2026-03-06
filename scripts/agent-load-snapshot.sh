#!/usr/bin/env bash
# agent-load-snapshot.sh — Capture context capacity % per agent
#
# Outputs a JSON snapshot of each agent's cognitive load.
# Used by: session-maintenance (auto-heal), agent-satisfaction (scoring), health checks.
#
# Usage:
#   agent-load-snapshot.sh              # human-readable table
#   agent-load-snapshot.sh --json       # machine-readable JSON
#   agent-load-snapshot.sh --check      # exit 1 if any agent overloaded (>85%)

set -eo pipefail

MODE="${1:-table}"
COMPOSE_DIR="/root/openclaw"
AGENTS=("relay" "main" "spec-projects" "spec-github" "spec-dev" "spec-reactor" "spec-browser" "spec-research" "spec-security" "spec-ops" "spec-design" "spec-systems" "spec-comms")
OVERLOAD_THRESHOLD=85
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

declare -a ROWS
any_overloaded=false

for agent in "${AGENTS[@]}"; do
  json=$(cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway openclaw sessions --agent "$agent" --json 2>/dev/null | grep -v "level=warning")
  [ -z "$json" ] && continue

  # Get the highest context % session for this agent (skip null token counts)
  peak=$(echo "$json" | jq -r '
    [.sessions // [] | .[] | select(.contextTokens > 0 and .totalTokens != null and .totalTokens > 0) |
     {key, pct: (.totalTokens / .contextTokens * 100 | floor), tokens: .totalTokens, ctx: .contextTokens, model}
    ] | sort_by(-.pct) | .[0] // empty
  ' 2>/dev/null)

  if [ -n "$peak" ] && [ "$peak" != "null" ]; then
    pct=$(echo "$peak" | jq -r '.pct')
    tokens=$(echo "$peak" | jq -r '.tokens')
    ctx=$(echo "$peak" | jq -r '.ctx')
    key=$(echo "$peak" | jq -r '.key')
    model=$(echo "$peak" | jq -r '.model // "unknown"')
  else
    pct=0; tokens=0; ctx=0; key="-"; model="-"
  fi

  # Determine state
  if [ "$pct" -gt 100 ]; then
    state="BROKEN"
    any_overloaded=true
  elif [ "$pct" -gt "$OVERLOAD_THRESHOLD" ]; then
    state="OVERLOADED"
    any_overloaded=true
  elif [ "$pct" -gt 70 ]; then
    state="STRAINED"
  elif [ "$pct" -gt 50 ]; then
    state="WORKING"
  else
    state="HEALTHY"
  fi

  ROWS+=("{\"agent\":\"$agent\",\"pct\":$pct,\"tokens\":$tokens,\"context\":$ctx,\"state\":\"$state\",\"model\":\"$model\",\"peakSession\":\"$key\"}")
done

if [ "$MODE" = "--json" ]; then
  echo "{\"timestamp\":\"$TIMESTAMP\",\"agents\":[$(IFS=,; echo "${ROWS[*]}")]}"
elif [ "$MODE" = "--check" ]; then
  if [ "$any_overloaded" = true ]; then
    echo "OVERLOADED agents detected:"
    for row in "${ROWS[@]}"; do
      state=$(echo "$row" | jq -r '.state')
      [ "$state" = "OVERLOADED" ] || [ "$state" = "BROKEN" ] && echo "  $(echo "$row" | jq -r '"\(.agent): \(.pct)% (\(.state))"')"
    done
    exit 1
  else
    echo "All agents healthy."
    exit 0
  fi
else
  printf "%-16s %6s  %-10s  %-20s  %s\n" "AGENT" "LOAD" "STATE" "MODEL" "PEAK SESSION"
  printf "%-16s %6s  %-10s  %-20s  %s\n" "-----" "----" "-----" "-----" "------------"
  for row in "${ROWS[@]}"; do
    agent=$(echo "$row" | jq -r '.agent')
    pct=$(echo "$row" | jq -r '.pct')
    state=$(echo "$row" | jq -r '.state')
    model=$(echo "$row" | jq -r '.model')
    key=$(echo "$row" | jq -r '.peakSession')
    printf "%-16s %5d%%  %-10s  %-20s  %s\n" "$agent" "$pct" "$state" "$model" "$key"
  done
fi
