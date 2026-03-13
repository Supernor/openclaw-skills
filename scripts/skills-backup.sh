#!/bin/bash
# skills-backup.sh — Push all skills + hooks to openclaw-skills repo
# Outputs structured JSON. Zero LLM tokens needed.
set -euo pipefail

REPO_PATH="/home/node/.openclaw/repos/openclaw-skills"
STATE_DIR="/home/node/.openclaw"

if [ ! -d "$REPO_PATH/.git" ]; then
  git clone https://github.com/Supernor/openclaw-skills.git "$REPO_PATH" 2>/dev/null
fi

cd "$REPO_PATH"
git pull -q origin main 2>/dev/null || true

COPIED=0

# Dynamic discovery: backs up skills from ALL workspace* directories
# Agent display name comes from agent-roster.json (built by skill-router)
ROSTER="$STATE_DIR/agent-roster.json"

workspace_to_agent() {
  local ws="$1"
  case "$ws" in
    workspace|workspace-main) echo "main" ;;
    workspace-*) echo "$ws" | sed 's/^workspace-//' ;;
    *) echo "$ws" ;;
  esac
}

agent_display_name() {
  local agent_id="$1"
  if [ -f "$ROSTER" ]; then
    local name
    name=$(jq -r --arg id "$agent_id" '.[] | select(.id == $id) | .name' "$ROSTER" 2>/dev/null)
    if [ -n "$name" ] && [ "$name" != "null" ]; then
      echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
      return
    fi
  fi
  echo "$agent_id"
}

for ws_skills in "$STATE_DIR"/workspace*/skills; do
  [ -d "$ws_skills" ] || continue
  WS_DIR=$(basename "$(dirname "$ws_skills")")
  AGENT_ID=$(workspace_to_agent "$WS_DIR")
  DISPLAY_NAME=$(agent_display_name "$AGENT_ID")

  for skill_dir in "$ws_skills"/*/; do
    [ -d "$skill_dir" ] || continue
    SKILL_NAME=$(basename "$skill_dir")
    mkdir -p "$REPO_PATH/$DISPLAY_NAME/$SKILL_NAME"
    cp "$skill_dir"* "$REPO_PATH/$DISPLAY_NAME/$SKILL_NAME/" 2>/dev/null && ((COPIED++)) || true
  done
done

# Hooks
if [ -d "$STATE_DIR/hooks" ]; then
  for hook_dir in "$STATE_DIR/hooks"/*/; do
    [ -d "$hook_dir" ] || continue
    HOOK_NAME=$(basename "$hook_dir")
    mkdir -p "$REPO_PATH/hooks/$HOOK_NAME"
    cp "$hook_dir"* "$REPO_PATH/hooks/$HOOK_NAME/" 2>/dev/null && ((COPIED++)) || true
  done
fi

# Scripts
if [ -d "$STATE_DIR/scripts" ]; then
  mkdir -p "$REPO_PATH/scripts"
  cp "$STATE_DIR/scripts/"*.sh "$REPO_PATH/scripts/" 2>/dev/null && ((COPIED++)) || true
fi

git add -A
if git diff --cached --quiet; then
  echo '{"status":"PASS","message":"No changes","pushed":false}'
else
  CHANGED=$(git diff --cached --stat | tail -1)
  git commit -q -m "[skills-backup] $(date -u +%Y-%m-%dT%H:%M:%SZ) auto-backup"
  if git push -q origin main 2>/dev/null; then
    echo '{"status":"PASS","message":"Skills backed up","pushed":true,"sha":"'"$(git rev-parse --short HEAD)"'","changes":"'"$CHANGED"'"}'
  else
    echo '{"status":"ERROR","message":"Push failed","pushed":false}'
    exit 1
  fi
fi
