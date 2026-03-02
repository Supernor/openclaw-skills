#!/usr/bin/env bash
# skill-router.sh — Build and query the dynamic skill routing index
# Scans all workspace skills, extracts frontmatter, builds a routing index.
# Captain uses this instead of hardcoded keyword lists.
#
# Usage:
#   skill-router.sh build          # Scan skills, rebuild index
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

# Map workspace dirs to agent IDs
workspace_to_agent() {
  case "$1" in
    workspace)              echo "main" ;;
    workspace-relay)        echo "relay" ;;
    workspace-spec-github)  echo "spec-github" ;;
    workspace-spec-projects) echo "spec-projects" ;;
    workspace-main)         echo "main" ;;
    *)                      echo "$1" ;;
  esac
}

# Agent display names
agent_name() {
  case "$1" in
    main)          echo "Captain" ;;
    relay)         echo "Relay" ;;
    spec-github)   echo "Repo-Man" ;;
    spec-projects) echo "Scribe" ;;
    *)             echo "$1" ;;
  esac
}

case "$CMD" in

  # ──── BUILD ────
  build)
    SKILLS="[]"

    for SKILL_FILE in $(find "${BASE}"/workspace*/skills -name skill.md 2>/dev/null | sort); do
      WS_DIR=$(echo "$SKILL_FILE" | sed "s|${BASE}/||;s|/skills/.*||")
      AGENT_ID=$(workspace_to_agent "$WS_DIR")
      SKILL_NAME=$(echo "$SKILL_FILE" | sed 's|.*/skills/||;s|/skill.md||')

      # Extract YAML frontmatter
      FRONT=$(sed -n '/^---$/,/^---$/p' "$SKILL_FILE" | grep -v '^---$')

      NAME=$(echo "$FRONT" | grep '^name:' | sed 's/^name: *//')
      DESC=$(echo "$FRONT" | grep '^description:' | sed 's/^description: *//')
      TAGS=$(echo "$FRONT" | grep '^tags:' | sed 's/^tags: *\[//;s/\].*//;s/, */,/g')
      VERSION=$(echo "$FRONT" | grep '^version:' | sed 's/^version: *//')

      # Check if user-invocable (has an invoke command like /skill-name)
      INVOCABLE="false"
      if grep -qiE '^\s*-\s*`?/' "$SKILL_FILE" 2>/dev/null || grep -qi 'user-invocable\|user invoke\|/'"$SKILL_NAME" "$SKILL_FILE" 2>/dev/null; then
        INVOCABLE="true"
      fi

      # Build keywords: tags + words from name + key words from description
      KEYWORDS="$TAGS"
      # Add name parts as keywords
      NAME_WORDS=$(echo "$SKILL_NAME" | tr '-' ',')
      KEYWORDS="${KEYWORDS},${NAME_WORDS}"

      SKILLS=$(echo "$SKILLS" | jq \
        --arg name "$SKILL_NAME" \
        --arg desc "$DESC" \
        --arg tags "$TAGS" \
        --arg agent "$AGENT_ID" \
        --arg agent_name "$(agent_name "$AGENT_ID")" \
        --arg version "$VERSION" \
        --argjson invocable "$INVOCABLE" \
        --arg keywords "$KEYWORDS" \
        --arg workspace "$WS_DIR" \
        '. + [{
          name: $name,
          description: $desc,
          tags: ($tags | split(",")),
          keywords: ($keywords | split(",") | map(select(. != ""))),
          agent: $agent,
          agent_name: $agent_name,
          version: $version,
          invocable: $invocable,
          workspace: $workspace
        }]')
    done

    # Build agent summary
    AGENTS=$(echo "$SKILLS" | jq '[group_by(.agent)[] | {
      agent: .[0].agent,
      name: .[0].agent_name,
      skill_count: length,
      skills: [.[].name],
      all_keywords: [.[].keywords[]] | unique
    }]')

    # Write index
    jq -n \
      --argjson skills "$SKILLS" \
      --argjson agents "$AGENTS" \
      --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{
        version: 1,
        built_at: $built_at,
        total_skills: ($skills | length),
        agents: $agents,
        skills: $skills
      }' > "$INDEX"

    TOTAL=$(echo "$SKILLS" | jq length)
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

  *)
    echo '{"error":"Unknown command: '"$CMD"'","usage":"skill-router.sh <build|route|list|index>"}' >&2
    exit 1
    ;;
esac
