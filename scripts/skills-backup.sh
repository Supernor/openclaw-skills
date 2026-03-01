#!/bin/bash
# skills-backup.sh — Push all skills + hooks to openclaw-skills repo
# Outputs structured JSON. Zero LLM tokens needed.
set -euo pipefail

REPO_PATH="/home/node/.openclaw/workspace-spec-github/openclaw-skills"
STATE_DIR="/home/node/.openclaw"

if [ ! -d "$REPO_PATH/.git" ]; then
  git clone https://github.com/NowThatJustMakesSense/openclaw-skills.git "$REPO_PATH" 2>/dev/null
fi

cd "$REPO_PATH"
git pull -q origin main 2>/dev/null || true

COPIED=0

# Captain workspace skills
if [ -d "$STATE_DIR/workspace/skills" ]; then
  for skill_dir in "$STATE_DIR/workspace/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    SKILL_NAME=$(basename "$skill_dir")
    mkdir -p "$REPO_PATH/captain/$SKILL_NAME"
    cp "$skill_dir"* "$REPO_PATH/captain/$SKILL_NAME/" 2>/dev/null && ((COPIED++)) || true
  done
fi

# Repo-Man skills
if [ -d "$STATE_DIR/workspace-spec-github/skills" ]; then
  for skill_dir in "$STATE_DIR/workspace-spec-github/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    SKILL_NAME=$(basename "$skill_dir")
    mkdir -p "$REPO_PATH/repo-man/$SKILL_NAME"
    cp "$skill_dir"* "$REPO_PATH/repo-man/$SKILL_NAME/" 2>/dev/null && ((COPIED++)) || true
  done
fi

# Quartermaster skills
if [ -d "$STATE_DIR/workspace-spec-projects/skills" ]; then
  for skill_dir in "$STATE_DIR/workspace-spec-projects/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    SKILL_NAME=$(basename "$skill_dir")
    mkdir -p "$REPO_PATH/quartermaster/$SKILL_NAME"
    cp "$skill_dir"* "$REPO_PATH/quartermaster/$SKILL_NAME/" 2>/dev/null && ((COPIED++)) || true
  done
fi

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
