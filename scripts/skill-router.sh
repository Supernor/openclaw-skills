#!/usr/bin/env bash
# skill-router.sh — Build and query the dynamic skill routing index
# Scans all workspace skills, extracts frontmatter, builds a routing index.
# Captain uses this instead of hardcoded keyword lists.
#
# Usage:
#   skill-router.sh build          # Scan skills, rebuild index (auto-discovers agents)
#   skill-router.sh build-roster   # Refresh agent name cache from openclaw.json
#   skill-router.sh route <query>  # Find best agent + skill for a query
#   skill-router.sh list [agent]   # List all skills (or per agent)
#   skill-router.sh index          # Dump the full index

set -eo pipefail

BASE="/home/node/.openclaw"
if [ ! -d "$BASE" ] && [ -d "/root/.openclaw" ]; then
  BASE="/root/.openclaw"
fi

INDEX="${BASE}/skill-router-index.json"

CMD="${1:?Usage: skill-router.sh <build|route|list|index>}"
shift

# Auto-generate agent roster from openclaw.json (cached)
_ensure_roster() {
  local roster="${BASE}/agent-roster.json"
  if [ ! -f "$roster" ] || [ "${BASE}/openclaw.json" -nt "$roster" ]; then
    if [ -f "${BASE}/openclaw.json" ]; then
      jq '.agents.list | map({id: .id, name: .name})' "${BASE}/openclaw.json" > "$roster" 2>/dev/null || true
    fi
  fi
}

# Map workspace dirs to agent IDs (pattern-based, no hardcoding)
workspace_to_agent() {
  local ws="$1"
  case "$ws" in
    workspace|workspace-main) echo "main" ;;
    workspace-*) echo "$ws" | sed 's/^workspace-//' ;;
    *) echo "$ws" ;;
  esac
}

# Agent display names — reads from cached roster, falls back to title-case
agent_name() {
  local agent_id="$1"
  local roster="${BASE}/agent-roster.json"
  if [ -f "$roster" ]; then
    local name
    name=$(jq -r --arg id "$agent_id" '.[] | select(.id == $id) | .name' "$roster" 2>/dev/null)
    if [ -n "$name" ] && [ "$name" != "null" ]; then
      echo "$name"
      return 0
    fi
  fi
  # Fallback: capitalize first letter of each segment
  echo "$agent_id" | sed 's/-/ /g; s/\b\(.\)/\U\1/g'
}

case "$CMD" in

  # ──── BUILD ────
  build)
    _ensure_roster
    TMPFILE=$(mktemp)
    echo '[]' > "$TMPFILE"
    JQ_FILTER=$(mktemp)
    cat > "$JQ_FILTER" << 'JQEOF'
. + [{
  name: $name,
  description: $desc,
  tags: ($tags | split(",") | map(select(length > 0))),
  keywords: ($keywords | split(",") | map(select(length > 0))),
  agent: $agent,
  agent_name: $agent_name,
  version: $version,
  invocable: $invocable,
  workspace: $workspace
}]
JQEOF

    for SKILL_FILE in $(find "${BASE}"/workspace*/skills -name "SKILL.md" -o -name "skill.md" 2>/dev/null | sort); do
      WS_DIR=$(echo "$SKILL_FILE" | sed "s|${BASE}/||;s|/skills/.*||")
      AGENT_ID=$(workspace_to_agent "$WS_DIR")
      SKILL_NAME=$(echo "$SKILL_FILE" | sed 's|.*/skills/||;s|/[Ss][Kk][Ii][Ll][Ll]\.[Mm][Dd]||')

      # Extract YAML frontmatter (skip skills without it)
      FRONT=$(sed -n '/^---$/,/^---$/p' "$SKILL_FILE" | grep -v '^---$' || true)
      if [ -z "$FRONT" ]; then
        continue
      fi

      NAME=$(echo "$FRONT" | grep '^name:' | head -1 | sed 's/^name: *//' || true)
      DESC=$(echo "$FRONT" | grep '^description:' | head -1 | sed 's/^description: *//' || true)
      TAGS=$(echo "$FRONT" | grep '^tags:' | head -1 | sed 's/^tags: *\[//;s/\].*//;s/, */,/g' || true)
      VERSION=$(echo "$FRONT" | grep '^version:' | head -1 | sed 's/^version: *//' || true)

      # Check if user-invocable
      INVOCABLE="false"
      if grep -qiE '^\s*-\s*`?/' "$SKILL_FILE" 2>/dev/null || grep -qi 'user-invocable\|user invoke\|/'"$SKILL_NAME" "$SKILL_FILE" 2>/dev/null; then
        INVOCABLE="true"
      fi

      # Build keywords from tags + skill name parts
      KEYWORDS="$TAGS"
      NAME_WORDS=$(echo "$SKILL_NAME" | tr '-' ',')
      KEYWORDS="${KEYWORDS},${NAME_WORDS}"

      # Append skill to temp file using filter file (avoids shell escaping issues)
      jq -f "$JQ_FILTER" \
        --arg name "$SKILL_NAME" \
        --arg desc "$DESC" \
        --arg tags "$TAGS" \
        --arg agent "$AGENT_ID" \
        --arg agent_name "$(agent_name "$AGENT_ID")" \
        --arg version "$VERSION" \
        --argjson invocable "$INVOCABLE" \
        --arg keywords "$KEYWORDS" \
        --arg workspace "$WS_DIR" \
        "$TMPFILE" > "${TMPFILE}.new" && mv "${TMPFILE}.new" "$TMPFILE"
    done

    # Build agent summary
    AGENTS=$(jq '[group_by(.agent)[] | {
      agent: .[0].agent,
      name: .[0].agent_name,
      skill_count: length,
      skills: [.[].name],
      all_keywords: [.[].keywords[]] | unique
    }]' "$TMPFILE")

    # Write index
    jq -n \
      --slurpfile skills "$TMPFILE" \
      --argjson agents "$AGENTS" \
      --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{
        version: 1,
        built_at: $built_at,
        total_skills: ($skills[0] | length),
        agents: $agents,
        skills: $skills[0]
      }' > "$INDEX"

    TOTAL=$(jq length "$TMPFILE")
    rm -f "$TMPFILE" "${TMPFILE}.new" "$JQ_FILTER"
    echo "{\"status\":\"ok\",\"skills\":$TOTAL,\"index\":\"$INDEX\"}"
    ;;

  # ──── ROUTE ────
  route)
    QUERY="${1:?Usage: skill-router.sh route <query>}"

    if [ ! -f "$INDEX" ]; then
      echo '{"error":"index not built, run: skill-router.sh build"}' >&2
      exit 1
    fi

    # Lowercase the query, split into words
    WORDS=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

    # Score each skill by keyword overlap
    jq --arg words "$WORDS" '
      ($words | split(",")) as $qwords |
      .skills | map(
        . as $skill |
        ($skill.keywords | map(ascii_downcase)) as $kw |
        ($qwords | map(select(. as $w | $kw | any(. == $w or startswith($w)))) | length) as $score |
        $skill + {score: $score}
      ) |
      sort_by(-.score) |
      map(select(.score > 0)) |
      .[0:5] |
      map({name, agent, agent_name, score, description, invocable})
    ' "$INDEX"
    ;;

  # ──── LIST ────
  list)
    AGENT="${1:-}"

    if [ ! -f "$INDEX" ]; then
      echo '{"error":"index not built, run: skill-router.sh build"}' >&2
      exit 1
    fi

    if [ -n "$AGENT" ]; then
      jq --arg agent "$AGENT" '.skills | map(select(.agent == $agent or .agent_name == $agent)) | map({name, description, tags, invocable})' "$INDEX"
    else
      jq '.agents | map({agent: .name, id: .agent, skills: .skill_count, skill_list: .skills})' "$INDEX"
    fi
    ;;

  # ──── INDEX ────
  index)
    if [ ! -f "$INDEX" ]; then
      echo '{"error":"index not built, run: skill-router.sh build"}' >&2
      exit 1
    fi
    cat "$INDEX"
    ;;

  # ──── BUILD-ROSTER ────
  build-roster)
    if [ ! -f "${BASE}/openclaw.json" ]; then
      echo '{"error":"openclaw.json not found"}' >&2
      exit 1
    fi
    ROSTER="${BASE}/agent-roster.json"
    jq '.agents.list | map({id: .id, name: .name})' "${BASE}/openclaw.json" > "$ROSTER"
    COUNT=$(jq 'length' "$ROSTER")
    echo "{\"status\":\"ok\",\"agents\":$COUNT,\"roster\":\"$ROSTER\"}"
    ;;

  *)
    echo '{"error":"Unknown command: '"$CMD"'","usage":"skill-router.sh <build|build-roster|route|list|index>"}' >&2
    exit 1
    ;;
esac
