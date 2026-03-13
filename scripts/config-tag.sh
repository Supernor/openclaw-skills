#!/bin/bash
# config-tag.sh — Tag current config state in openclaw-config repo
# Usage: config-tag.sh [label]
# Creates a git tag like config-2026-03-01-label for easy rollback reference
set -euo pipefail

REPO_PATH="/home/node/.openclaw/repos/openclaw-config"
LABEL="${1:-snapshot}"
DATE=$(date -u +%Y-%m-%d)
TAG="config-${DATE}-${LABEL}"

cd "$REPO_PATH"
git pull -q origin main 2>/dev/null || true

if git tag -l "$TAG" | grep -q "$TAG"; then
  # Tag exists, append sequence number
  SEQ=2
  while git tag -l "${TAG}-${SEQ}" | grep -q "${TAG}-${SEQ}"; do ((SEQ++)); done
  TAG="${TAG}-${SEQ}"
fi

git tag -a "$TAG" -m "Config snapshot: $LABEL ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
git push origin "$TAG" -q 2>/dev/null

echo '{"status":"PASS","tag":"'"$TAG"'","repo":"openclaw-config"}'
