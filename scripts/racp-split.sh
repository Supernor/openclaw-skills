#!/usr/bin/env bash
# racp-split.sh — RACP Transform: split a marked-up source file into per-agent versions
# Reads RACP audience markers and generates targeted output per agent.
#
# Marker syntax:
#   📡 = Shared (all agents get this block)
#   👤 = Human-facing only (relay)
#   ⚙️ = All agents (internal/system)
#   ⚙️:agent-id = Targeted to specific agent (relay, main, spec-github, spec-projects)
#   ⚙️:agent1,agent2 = Targeted to multiple agents
#   No marker = treated as 📡 (shared)
#
# Usage: racp-split.sh <source-file> <output-dir>
# Output: one file per agent in output-dir, named <agent-id>.md
#         plus summary JSON on stdout

set -eo pipefail

SOURCE="${1:?Usage: racp-split.sh <source-file> <output-dir>}"
OUTDIR="${2:?Usage: racp-split.sh <source-file> <output-dir>}"

# Dynamic agent discovery from roster (built by skill-router.sh build)
BASE="/home/node/.openclaw"
[ ! -d "$BASE" ] && [ -d "/root/.openclaw" ] && BASE="/root/.openclaw"
ROSTER="$BASE/agent-roster.json"

if [ -f "$ROSTER" ]; then
  mapfile -t AGENTS < <(jq -r '.[].id' "$ROSTER")
  AGENT_NAMES=$(jq -c 'map({(.id): .name}) | add' "$ROSTER")
else
  echo '{"error":"agent-roster.json not found. Run: skill-router.sh build-roster"}' >&2
  exit 1
fi

if [ ! -f "$SOURCE" ]; then
  echo "{\"error\":\"Source file not found: $SOURCE\"}"
  exit 1
fi

mkdir -p "$OUTDIR"

# Initialize output files with header
BASENAME=$(basename "$SOURCE" .md)
for agent in "${AGENTS[@]}"; do
  > "${OUTDIR}/${agent}.md"
done

# Parse the source file
# State machine: track current audience marker, accumulate lines
current_audience="shared"  # default: everyone gets it
current_targets=""          # specific agent IDs when targeted

flush_block() {
  local block="$1"
  [ -z "$block" ] && return

  case "$current_audience" in
    shared)
      for agent in "${AGENTS[@]}"; do
        echo "$block" >> "${OUTDIR}/${agent}.md"
      done
      ;;
    human)
      echo "$block" >> "${OUTDIR}/relay.md"
      ;;
    all-agents)
      for agent in "${AGENTS[@]}"; do
        echo "$block" >> "${OUTDIR}/${agent}.md"
      done
      ;;
    targeted)
      IFS=',' read -ra targets <<< "$current_targets"
      for target in "${targets[@]}"; do
        target=$(echo "$target" | tr -d ' ')
        if [ -f "${OUTDIR}/${target}.md" ]; then
          echo "$block" >> "${OUTDIR}/${target}.md"
        fi
      done
      ;;
  esac
}

block=""
while IFS= read -r line || [ -n "$line" ]; do
  # Check for RACP markers at start of line (possibly after ## heading markup)
  # Markers: 📡, 👤, ⚙️, ⚙️:target
  stripped=$(echo "$line" | sed 's/^#* *//')

  if echo "$stripped" | grep -qP '^\x{1f4e1}' 2>/dev/null || echo "$stripped" | grep -q '^📡'; then
    # Flush previous block
    flush_block "$block"
    block=""
    current_audience="shared"
    # Keep the line content after the marker
    content=$(echo "$line" | sed 's/📡[[:space:]]*//')
    [ -n "$content" ] && block="$content"

  elif echo "$stripped" | grep -qP '^\x{1f464}' 2>/dev/null || echo "$stripped" | grep -q '^👤'; then
    flush_block "$block"
    block=""
    current_audience="human"
    content=$(echo "$line" | sed 's/👤[[:space:]]*//')
    [ -n "$content" ] && block="$content"

  elif echo "$stripped" | grep -q '^⚙️:'; then
    flush_block "$block"
    block=""
    current_audience="targeted"
    # Extract targets after ⚙️:
    current_targets=$(echo "$stripped" | sed 's/^⚙️:\([a-z,\-]*\).*/\1/')
    content=$(echo "$line" | sed 's/⚙️:[a-z,\-]*[[:space:]]*//')
    [ -n "$content" ] && block="$content"

  elif echo "$stripped" | grep -q '^⚙️'; then
    flush_block "$block"
    block=""
    current_audience="all-agents"
    content=$(echo "$line" | sed 's/⚙️[[:space:]]*//')
    [ -n "$content" ] && block="$content"

  else
    # Accumulate into current block
    if [ -z "$block" ]; then
      block="$line"
    else
      block="${block}
${line}"
    fi
  fi
done < "$SOURCE"

# Flush final block
flush_block "$block"

# Clean up: remove trailing blank lines from each file
for agent in "${AGENTS[@]}"; do
  outfile="${OUTDIR}/${agent}.md"
  if [ -s "$outfile" ]; then
    # Remove leading/trailing blank lines
    sed -i '/./,$!d' "$outfile"
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$outfile"
  fi
done

# Generate summary JSON
echo "{"
echo "  \"source\": \"$SOURCE\","
echo "  \"outputs\": {"
first=true
for agent in "${AGENTS[@]}"; do
  outfile="${OUTDIR}/${agent}.md"
  chars=$(wc -c < "$outfile" 2>/dev/null || echo 0)
  lines=$(wc -l < "$outfile" 2>/dev/null || echo 0)
  tokens=$(awk "BEGIN{printf \"%d\", ${chars}/4}")
  name=$(echo "$AGENT_NAMES" | jq -r ".\"${agent}\"" 2>/dev/null || echo "$agent")

  if [ "$first" = true ]; then
    first=false
  else
    echo ","
  fi
  printf "    \"%s\": {\"name\":\"%s\", \"chars\":%d, \"lines\":%d, \"est_tokens\":%d}" "$agent" "$name" "$chars" "$lines" "$tokens"
done
echo ""
echo "  },"

# Source stats
src_chars=$(wc -c < "$SOURCE")
src_tokens=$(awk "BEGIN{printf \"%d\", ${src_chars}/4}")
echo "  \"source_chars\": $src_chars,"
echo "  \"source_tokens\": $src_tokens,"

# Savings calculation
total_split=0
for agent in "${AGENTS[@]}"; do
  outfile="${OUTDIR}/${agent}.md"
  chars=$(wc -c < "$outfile" 2>/dev/null || echo 0)
  total_split=$((total_split + chars))
done
blanket_total=$((src_chars * 4))
savings=$((blanket_total - total_split))
savings_tokens=$(awk "BEGIN{printf \"%d\", ${savings}/4}")
echo "  \"blanket_total_chars\": $blanket_total,"
echo "  \"split_total_chars\": $total_split,"
echo "  \"savings_chars\": $savings,"
echo "  \"savings_tokens\": $savings_tokens"
echo "}"
