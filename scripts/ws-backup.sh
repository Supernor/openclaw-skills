#!/bin/bash
# ws-backup.sh — Commit and push all workspace MD files to openclaw-workspace repo
# Outputs structured JSON. Zero LLM tokens needed.
set -euo pipefail

REPO_PATH="/home/node/.openclaw/workspace-spec-github/openclaw-workspace"
STATE_DIR="/home/node/.openclaw"

if [ ! -d "$REPO_PATH/.git" ]; then
  git clone https://github.com/Supernor/openclaw-workspace.git "$REPO_PATH" 2>/dev/null
fi

cd "$REPO_PATH"
git pull -q origin main 2>/dev/null || true

# Copy workspace files — all agents, MD only, skip skills (separate repo)
# Dynamic discovery: backs up any workspace* directory automatically
COPIED=0
for SRC_PATH in "$STATE_DIR"/workspace*/; do
  [ -d "$SRC_PATH" ] || continue
  SRC_DIR=$(basename "$SRC_PATH")
  DEST_DIR="$SRC_DIR"

  if [ -d "$SRC_PATH" ]; then
    mkdir -p "$REPO_PATH/$DEST_DIR"
    # Copy MD files at root level
    for f in "$SRC_PATH"/*.md; do
      [ -f "$f" ] && cp "$f" "$REPO_PATH/$DEST_DIR/" && ((COPIED++)) || true
    done
    # Copy memory/ subdirectory if present
    if [ -d "$SRC_PATH/memory" ]; then
      mkdir -p "$REPO_PATH/$DEST_DIR/memory"
      for f in "$SRC_PATH/memory/"*.md; do
        [ -f "$f" ] && cp "$f" "$REPO_PATH/$DEST_DIR/memory/" && ((COPIED++)) || true
      done
    fi
    # Copy decisions/ subdirectory if present
    if [ -d "$SRC_PATH/decisions" ]; then
      mkdir -p "$REPO_PATH/$DEST_DIR/decisions"
      for f in "$SRC_PATH/decisions/"*.md; do
        [ -f "$f" ] && cp "$f" "$REPO_PATH/$DEST_DIR/decisions/" && ((COPIED++)) || true
      done
    fi
    # Copy logs (for Repo-Man)
    if [ -d "$SRC_PATH/logs" ]; then
      mkdir -p "$REPO_PATH/$DEST_DIR/logs"
      cp "$SRC_PATH/logs/"*.log "$REPO_PATH/$DEST_DIR/logs/" 2>/dev/null || true
    fi
  fi
done

# Commit and push
git add -A
if git diff --cached --quiet; then
  echo '{"status":"PASS","message":"No changes","files_checked":'"$COPIED"',"pushed":false}'
else
  CHANGED=$(git diff --cached --stat | tail -1)
  git commit -m "[ws-backup] $(date -u +%Y-%m-%dT%H:%M:%SZ) auto-backup" -q
  if git push origin main -q 2>/dev/null; then
    echo '{"status":"PASS","message":"Workspace backed up","files_checked":'"$COPIED"',"pushed":true,"sha":"'"$(git rev-parse --short HEAD)"'","changes":"'"$CHANGED"'"}'
  else
    echo '{"status":"ERROR","message":"Commit succeeded but push failed","pushed":false}'
    exit 1
  fi
fi
