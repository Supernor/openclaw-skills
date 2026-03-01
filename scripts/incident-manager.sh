#!/bin/bash
# incident-manager.sh — Create/close GitHub Issues for model health incidents
# Usage:
#   incident-manager.sh open <provider> <reason> <message>
#   incident-manager.sh close <provider> [message]
#   incident-manager.sh list
#   incident-manager.sh check <provider>  — returns open issue number or "none"
set -euo pipefail

REPO="NowThatJustMakesSense/openclaw-config"
ACTION="${1:?Usage: incident-manager.sh open|close|list|check [args]}"

case "$ACTION" in
  open)
    PROVIDER="${2:?}"
    REASON="${3:?}"
    MESSAGE="${4:-Provider $PROVIDER is experiencing issues}"

    # Check if there's already an open issue for this provider
    EXISTING=$(gh issue list --repo "$REPO" --label "provider:$PROVIDER" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
    if [ -n "$EXISTING" ]; then
      # Add comment to existing issue instead of creating duplicate
      gh issue comment "$EXISTING" --repo "$REPO" --body "**Update $(date -u +%Y-%m-%dT%H:%M:%SZ):** $MESSAGE" 2>/dev/null
      echo '{"action":"comment","issue":'"$EXISTING"',"provider":"'"$PROVIDER"'"}'
      exit 0
    fi

    # Create new issue
    ISSUE_NUM=$(gh issue create --repo "$REPO" \
      --title "🚨 Provider Down: $PROVIDER ($REASON)" \
      --body "## Incident Report

**Provider:** $PROVIDER
**Reason:** $REASON
**Detected:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Message:** $MESSAGE

## Impact
Provider is unavailable. Fallback chain may be degraded.

## Resolution
Issue will be automatically closed when provider recovers.
Manual close: \`/model-clear $PROVIDER\`" \
      --label "incident,provider:$PROVIDER,automated" 2>/dev/null | grep -o '[0-9]*$')

    echo '{"action":"opened","issue":'"${ISSUE_NUM:-0}"',"provider":"'"$PROVIDER"'","reason":"'"$REASON"'"}'
    ;;

  close)
    PROVIDER="${2:?}"
    MESSAGE="${3:-Provider $PROVIDER has recovered}"

    ISSUES=$(gh issue list --repo "$REPO" --label "provider:$PROVIDER" --state open --json number --jq '.[].number' 2>/dev/null || true)
    CLOSED=0
    for num in $ISSUES; do
      gh issue close "$num" --repo "$REPO" --comment "**Resolved $(date -u +%Y-%m-%dT%H:%M:%SZ):** $MESSAGE" 2>/dev/null
      ((CLOSED++))
    done
    echo '{"action":"closed","count":'"$CLOSED"',"provider":"'"$PROVIDER"'"}'
    ;;

  list)
    gh issue list --repo "$REPO" --label "incident" --state open --json number,title,createdAt,labels 2>/dev/null || echo '[]'
    ;;

  check)
    PROVIDER="${2:?}"
    RESULT=$(gh issue list --repo "$REPO" --label "provider:$PROVIDER" --state open --json number --jq '.[0].number // "none"' 2>/dev/null || echo "none")
    echo '{"provider":"'"$PROVIDER"'","open_issue":"'"$RESULT"'"}'
    ;;

  *)
    echo '{"error":"Unknown action: '"$ACTION"'"}'
    exit 1
    ;;
esac
