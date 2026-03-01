#!/usr/bin/env bash
# skill-audit.sh — Audit all skills for broken dependencies
# Scans skill.md files for referenced scripts, paths, channels, and skills.
# Verifies each reference exists. Reports missing/broken dependencies.
#
# Usage: skill-audit.sh [--verbose]

set -eo pipefail

BASE="/home/node/.openclaw"
VERBOSE=false
[ "${1:-}" = "--verbose" ] && VERBOSE=true

SKILLS_DIRS=(
  "${BASE}/workspace/skills"
  "${BASE}/workspace-spec-github/skills"
  "${BASE}/workspace-spec-projects/skills"
)

TOTAL_SKILLS=0
TOTAL_DEPS=0
TOTAL_MISSING=0
TOTAL_WARNINGS=0
ISSUES="[]"
SKILL_MAP="[]"

for SKILLS_DIR in "${SKILLS_DIRS[@]}"; do
  [ -d "$SKILLS_DIR" ] || continue
  WORKSPACE=$(basename "$(dirname "$SKILLS_DIR")")

  for SKILL_DIR in "$SKILLS_DIR"/*/; do
    [ -d "$SKILL_DIR" ] || continue
    SKILL_NAME=$(basename "$SKILL_DIR")
    SKILL_FILE="${SKILL_DIR}skill.md"
    [ -f "$SKILL_FILE" ] || continue

    TOTAL_SKILLS=$((TOTAL_SKILLS + 1))
    # Strip fenced code blocks (```) to avoid matching template examples
    CONTENT=$(cat "$SKILL_FILE" | awk '/^```/{skip=!skip;next} !skip{print}')
    DEPS="[]"
    SKILL_ISSUES="[]"

    # ── Check referenced scripts ──
    SCRIPTS=$(echo "$CONTENT" | grep -oE '[a-z_-]+\.sh' | sort -u || true)
    for SCRIPT in $SCRIPTS; do
      TOTAL_DEPS=$((TOTAL_DEPS + 1))
      SCRIPT_PATH="${BASE}/scripts/${SCRIPT}"
      if [ -f "$SCRIPT_PATH" ]; then
        if [ -x "$SCRIPT_PATH" ]; then
          STATUS="ok"
        else
          STATUS="not-executable"
          TOTAL_WARNINGS=$((TOTAL_WARNINGS + 1))
          SKILL_ISSUES=$(echo "$SKILL_ISSUES" | jq --arg s "$SCRIPT" --arg t "warning" '. + [{ref: $s, type: $t, issue: "script exists but not executable"}]')
        fi
      else
        STATUS="missing"
        TOTAL_MISSING=$((TOTAL_MISSING + 1))
        SKILL_ISSUES=$(echo "$SKILL_ISSUES" | jq --arg s "$SCRIPT" --arg t "error" '. + [{ref: $s, type: $t, issue: "script not found"}]')
      fi
      DEPS=$(echo "$DEPS" | jq --arg s "$SCRIPT" --arg st "$STATUS" '. + [{type: "script", ref: $s, status: $st}]')
    done

    # ── Check referenced JSON files ──
    JSON_FILES=$(echo "$CONTENT" | grep -oE '(registry|model-health|auth-profiles|openclaw|ops)\.json[l]?' | sort -u || true)
    for JF in $JSON_FILES; do
      TOTAL_DEPS=$((TOTAL_DEPS + 1))
      # Try common locations
      FOUND=false
      for CHECK_PATH in "${BASE}/${JF}" "${BASE}/logs/${JF}"; do
        if [ -f "$CHECK_PATH" ]; then
          FOUND=true
          break
        fi
      done
      if [ "$FOUND" = true ]; then
        DEPS=$(echo "$DEPS" | jq --arg s "$JF" '. + [{type: "file", ref: $s, status: "ok"}]')
      else
        # Not necessarily an error — could be a relative reference
        DEPS=$(echo "$DEPS" | jq --arg s "$JF" '. + [{type: "file", ref: $s, status: "assumed"}]')
      fi
    done

    # ── Check referenced channel IDs ──
    CHANNEL_REFS=$(echo "$CONTENT" | grep -oE '[0-9]{18,20}' | sort -u || true)
    REGISTRY_CHANNELS=$(jq -r '.discord.channels | to_entries[] | .value' "$BASE/registry.json" 2>/dev/null || true)
    for CID in $CHANNEL_REFS; do
      TOTAL_DEPS=$((TOTAL_DEPS + 1))
      if echo "$REGISTRY_CHANNELS" | grep -q "^${CID}$"; then
        DEPS=$(echo "$DEPS" | jq --arg s "$CID" '. + [{type: "channel", ref: $s, status: "ok"}]')
      else
        # Could be other IDs (guild, message, etc) — just note it
        DEPS=$(echo "$DEPS" | jq --arg s "$CID" '. + [{type: "id", ref: $s, status: "unverified"}]')
      fi
    done

    # ── Check referenced skills (cross-skill dependencies) ──
    SKILL_REFS=$(echo "$CONTENT" | grep -oE 'Run `[a-z_-]+`|run `[a-z_-]+`|skills/[a-z_-]+' | sed 's/.*`//;s/`.*//' | sed 's|skills/||' | sort -u || true)
    for SR in $SKILL_REFS; do
      [ "$SR" = "$SKILL_NAME" ] && continue  # skip self-reference
      TOTAL_DEPS=$((TOTAL_DEPS + 1))
      FOUND_SKILL=false
      for SD in "${SKILLS_DIRS[@]}"; do
        if [ -d "${SD}/${SR}" ]; then
          FOUND_SKILL=true
          break
        fi
      done
      if [ "$FOUND_SKILL" = true ]; then
        DEPS=$(echo "$DEPS" | jq --arg s "$SR" '. + [{type: "skill", ref: $s, status: "ok"}]')
      else
        # Might be a command name, not a skill
        DEPS=$(echo "$DEPS" | jq --arg s "$SR" '. + [{type: "skill-ref", ref: $s, status: "unverified"}]')
      fi
    done

    # ── Check cursor file references ──
    CURSOR_REFS=$(echo "$CONTENT" | grep -oE '[a-z_-]+-cursor\.txt' | sort -u || true)
    for CF in $CURSOR_REFS; do
      TOTAL_DEPS=$((TOTAL_DEPS + 1))
      if [ -f "${BASE}/${CF}" ]; then
        DEPS=$(echo "$DEPS" | jq --arg s "$CF" '. + [{type: "cursor", ref: $s, status: "ok"}]')
      else
        TOTAL_WARNINGS=$((TOTAL_WARNINGS + 1))
        DEPS=$(echo "$DEPS" | jq --arg s "$CF" '. + [{type: "cursor", ref: $s, status: "missing"}]')
        SKILL_ISSUES=$(echo "$SKILL_ISSUES" | jq --arg s "$CF" --arg t "warning" '. + [{ref: $s, type: $t, issue: "cursor file not initialized"}]')
      fi
    done

    # Build skill entry
    DEP_COUNT=$(echo "$DEPS" | jq 'length')
    ISSUE_COUNT=$(echo "$SKILL_ISSUES" | jq 'length')
    SKILL_MAP=$(echo "$SKILL_MAP" | jq \
      --arg name "$SKILL_NAME" \
      --arg ws "$WORKSPACE" \
      --argjson deps "$DEPS" \
      --argjson issues "$SKILL_ISSUES" \
      --argjson depCount "$DEP_COUNT" \
      --argjson issueCount "$ISSUE_COUNT" \
      '. + [{name: $name, workspace: $ws, dependencies: $depCount, issues: $issueCount, deps: $deps, issueDetails: $issues}]')

    if [ "$ISSUE_COUNT" -gt 0 ]; then
      ISSUES=$(echo "$ISSUES" | jq \
        --arg name "$SKILL_NAME" \
        --argjson details "$SKILL_ISSUES" \
        '. + [{skill: $name, issues: $details}]')
    fi
  done
done

# ── Check orphan scripts (scripts not referenced by any skill) ──
ALL_REFERENCED=$(echo "$SKILL_MAP" | jq -r '.[].deps[] | select(.type == "script") | .ref' | sort -u)
ORPHAN_SCRIPTS="[]"
for SCRIPT in "${BASE}"/scripts/*.sh; do
  [ -f "$SCRIPT" ] || continue
  SNAME=$(basename "$SCRIPT")
  if ! echo "$ALL_REFERENCED" | grep -q "^${SNAME}$"; then
    ORPHAN_SCRIPTS=$(echo "$ORPHAN_SCRIPTS" | jq --arg s "$SNAME" '. + [$s]')
  fi
done

# ── Summary output ──
if [ "$VERBOSE" = true ]; then
  SKILL_OUTPUT="$SKILL_MAP"
else
  SKILL_OUTPUT=$(echo "$SKILL_MAP" | jq '[.[] | {name, workspace, dependencies, issues}]')
fi

jq -n \
  --argjson totalSkills "$TOTAL_SKILLS" \
  --argjson totalDeps "$TOTAL_DEPS" \
  --argjson totalMissing "$TOTAL_MISSING" \
  --argjson totalWarnings "$TOTAL_WARNINGS" \
  --argjson skills "$SKILL_OUTPUT" \
  --argjson issues "$ISSUES" \
  --argjson orphanScripts "$ORPHAN_SCRIPTS" \
  '{
    summary: {
      skills: $totalSkills,
      dependencies: $totalDeps,
      missing: $totalMissing,
      warnings: $totalWarnings,
      status: (if $totalMissing > 0 then "FAIL" elif $totalWarnings > 0 then "WARN" else "PASS" end)
    },
    skills: $skills,
    issues: (if ($issues | length) > 0 then $issues else "none" end),
    orphanScripts: $orphanScripts
  }'
