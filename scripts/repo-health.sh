#!/bin/bash
# repo-health.sh — Verify all 3 GitHub repos, check ages, secrets count
# Outputs structured JSON. Zero LLM tokens needed.
set -euo pipefail

REPOS=("openclaw-config" "openclaw-workspace" "openclaw-skills")
CANONICAL_KEY_COUNT=9
NOW=$(date +%s)
SEVEN_DAYS=$((7 * 86400))

RESULTS="["
FIRST=true
ALL_OK=true

for repo in "${REPOS[@]}"; do
  if ! $FIRST; then RESULTS+=","; fi
  FIRST=false

  REPO_DATA=$(gh api "repos/Supernor/$repo" 2>/dev/null || echo '{"error":true}')
  if echo "$REPO_DATA" | jq -e '.error' >/dev/null 2>&1; then
    RESULTS+='{"repo":"'"$repo"'","reachable":false,"status":"ERROR"}'
    ALL_OK=false
    continue
  fi

  PUSHED_AT=$(echo "$REPO_DATA" | jq -r '.pushed_at // "unknown"')
  PRIVATE=$(echo "$REPO_DATA" | jq -r '.private')

  # Check age
  if [ "$PUSHED_AT" != "unknown" ]; then
    PUSH_EPOCH=$(date -d "$PUSHED_AT" +%s 2>/dev/null || echo 0)
    AGE_SECONDS=$((NOW - PUSH_EPOCH))
    AGE_DAYS=$((AGE_SECONDS / 86400))
    STALE=$( [ $AGE_SECONDS -gt $SEVEN_DAYS ] && echo true || echo false )
  else
    AGE_DAYS=-1
    STALE=true
  fi

  if $STALE; then ALL_OK=false; fi

  RESULTS+='{"repo":"'"$repo"'","reachable":true,"private":'"$PRIVATE"',"pushed_at":"'"$PUSHED_AT"'","age_days":'"$AGE_DAYS"',"stale":'"$STALE"'}'
done
RESULTS+="]"

# Check GitHub secrets count
SECRETS_COUNT=$(gh secret list --repo Supernor/openclaw-config --json name 2>/dev/null | jq 'length' 2>/dev/null || echo -1)
SECRETS_MATCH=$( [ "$SECRETS_COUNT" -eq "$CANONICAL_KEY_COUNT" ] && echo true || echo false )
if ! $SECRETS_MATCH; then ALL_OK=false; fi

# Local log health
LOG="/home/node/.openclaw/workspace-spec-github/logs/repo-man.log"
if [ -f "$LOG" ]; then
  LOG_LINES=$(wc -l < "$LOG")
  LOG_SIZE=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
  LOG_EXISTS=true
else
  LOG_LINES=0
  LOG_SIZE=0
  LOG_EXISTS=false
fi

STATUS=$( $ALL_OK && echo "PASS" || echo "WARN" )

cat << EOF
{
  "status": "$STATUS",
  "repos": $RESULTS,
  "secrets": {"count": $SECRETS_COUNT, "expected": $CANONICAL_KEY_COUNT, "match": $SECRETS_MATCH},
  "local_log": {"exists": $LOG_EXISTS, "lines": $LOG_LINES, "bytes": $LOG_SIZE},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
