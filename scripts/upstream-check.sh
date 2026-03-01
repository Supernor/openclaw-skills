#!/usr/bin/env bash
# upstream-check.sh — Check upstream PR and discussion for new activity
# Lightweight alternative to full github-feed for faster response times.
# Reads tracking config from registry.json, uses cursor for delta detection.
#
# Usage: upstream-check.sh [--quiet]
# --quiet: only output if there's new activity (for cron use)

set -eo pipefail

BASE="/home/node/.openclaw"
REGISTRY="${BASE}/registry.json"
CURSOR_FILE="${BASE}/upstream-feed-cursor.txt"

if [ ! -f "$REGISTRY" ]; then
  echo '{"error":"registry.json not found"}'
  exit 1
fi

UPSTREAM_REPO=$(jq -r '.github.upstream.repo' "$REGISTRY")
UPSTREAM_PR=$(jq -r '.github.upstream.pr' "$REGISTRY")
UPSTREAM_DISCUSSION=$(jq -r '.github.upstream.discussion' "$REGISTRY")
QUIET=false
[ "${1:-}" = "--quiet" ] && QUIET=true

# Read cursor
CURSOR="1970-01-01T00:00:00Z"
[ -f "$CURSOR_FILE" ] && CURSOR=$(cat "$CURSOR_FILE")

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── PR Activity ──
PR_COMMENTS=0
PR_REVIEWS=0
PR_STATE=""
PR_MERGED=false
PR_DETAILS="[]"

if [ "$UPSTREAM_PR" != "null" ] && [ -n "$UPSTREAM_PR" ]; then
  # Issue comments (general discussion)
  RAW=$(gh api "repos/${UPSTREAM_REPO}/issues/${UPSTREAM_PR}/comments" --jq "[.[] | select(.created_at > \"${CURSOR}\")] | length" 2>/dev/null || echo "0")
  PR_COMMENTS=$((PR_COMMENTS + RAW))

  # Review comments (inline code comments)
  RAW=$(gh api "repos/${UPSTREAM_REPO}/pulls/${UPSTREAM_PR}/comments" --jq "[.[] | select(.created_at > \"${CURSOR}\")] | length" 2>/dev/null || echo "0")
  PR_COMMENTS=$((PR_COMMENTS + RAW))

  # Reviews
  PR_REVIEWS=$(gh api "repos/${UPSTREAM_REPO}/pulls/${UPSTREAM_PR}/reviews" --jq "[.[] | select(.submitted_at > \"${CURSOR}\")] | length" 2>/dev/null || echo "0")

  # PR state
  PR_INFO=$(gh api "repos/${UPSTREAM_REPO}/pulls/${UPSTREAM_PR}" --jq '{state, merged, mergeable_state, title}' 2>/dev/null || echo '{}')
  PR_STATE=$(echo "$PR_INFO" | jq -r '.state // "unknown"')
  PR_MERGED=$(echo "$PR_INFO" | jq -r '.merged // false')

  # Grab recent comment details (last 3 new ones)
  if [ "$PR_COMMENTS" -gt 0 ]; then
    PR_DETAILS=$(gh api "repos/${UPSTREAM_REPO}/issues/${UPSTREAM_PR}/comments" \
      --jq "[.[] | select(.created_at > \"${CURSOR}\") | {author: .user.login, created: .created_at, body: (.body | split(\"\n\")[0] | if length > 100 then .[0:100] + \"...\" else . end), type: \"comment\"}] | last(3; .)" 2>/dev/null || echo "[]")
  fi

  # Grab recent review details
  if [ "$PR_REVIEWS" -gt 0 ]; then
    REVIEW_DETAILS=$(gh api "repos/${UPSTREAM_REPO}/pulls/${UPSTREAM_PR}/reviews" \
      --jq "[.[] | select(.submitted_at > \"${CURSOR}\") | {author: .user.login, created: .submitted_at, body: (if .body != \"\" and .body != null then (.body | split(\"\n\")[0] | if length > 100 then .[0:100] + \"...\" else . end) else .state end), type: \"review\"}] | last(3; .)" 2>/dev/null || echo "[]")
    PR_DETAILS=$(echo "$PR_DETAILS" "$REVIEW_DETAILS" | jq -sc '.[0] + .[1]')
  fi
fi

# ── Discussion Activity ──
DISC_REPLIES=0
DISC_DETAILS="[]"

if [ "$UPSTREAM_DISCUSSION" != "null" ] && [ -n "$UPSTREAM_DISCUSSION" ]; then
  DISC_RAW=$(gh api graphql -f query="
  {
    repository(owner: \"$(echo $UPSTREAM_REPO | cut -d/ -f1)\", name: \"$(echo $UPSTREAM_REPO | cut -d/ -f2)\") {
      discussion(number: ${UPSTREAM_DISCUSSION}) {
        comments(last: 10) {
          nodes { author { login } createdAt bodyText }
        }
      }
    }
  }" 2>/dev/null || echo '{}')

  DISC_REPLIES=$(echo "$DISC_RAW" | jq "[.data.repository.discussion.comments.nodes[] | select(.createdAt > \"${CURSOR}\")] | length" 2>/dev/null || echo "0")

  if [ "$DISC_REPLIES" -gt 0 ]; then
    DISC_DETAILS=$(echo "$DISC_RAW" | jq "[.data.repository.discussion.comments.nodes[] | select(.createdAt > \"${CURSOR}\") | {author: .author.login, created: .createdAt, body: (.bodyText | split(\"\n\")[0] | if length > 100 then .[0:100] + \"...\" else . end), type: \"reply\"}]" 2>/dev/null || echo "[]")
  fi
fi

# ── Compute totals ──
TOTAL_NEW=$((PR_COMMENTS + PR_REVIEWS + DISC_REPLIES))
HAS_ACTIVITY=false
[ "$TOTAL_NEW" -gt 0 ] && HAS_ACTIVITY=true

# Check for state changes
STATE_CHANGED=false
LAST_STATE=$(jq -r '.lastPrState // "open"' "${BASE}/upstream-check-state.json" 2>/dev/null || echo "open")
if [ "$PR_STATE" != "$LAST_STATE" ] && [ "$PR_STATE" != "unknown" ]; then
  STATE_CHANGED=true
  HAS_ACTIVITY=true
fi

# ── Output ──
if [ "$QUIET" = true ] && [ "$HAS_ACTIVITY" = false ]; then
  exit 0
fi

RESULT=$(jq -n \
  --arg ts "$NOW" \
  --arg cursor "$CURSOR" \
  --arg repo "$UPSTREAM_REPO" \
  --argjson pr "$UPSTREAM_PR" \
  --argjson discussion "$UPSTREAM_DISCUSSION" \
  --argjson prComments "$PR_COMMENTS" \
  --argjson prReviews "$PR_REVIEWS" \
  --arg prState "$PR_STATE" \
  --argjson prMerged "$PR_MERGED" \
  --argjson prDetails "$PR_DETAILS" \
  --argjson discReplies "$DISC_REPLIES" \
  --argjson discDetails "$DISC_DETAILS" \
  --argjson totalNew "$TOTAL_NEW" \
  --argjson hasActivity "$HAS_ACTIVITY" \
  --argjson stateChanged "$STATE_CHANGED" \
  --arg lastState "$LAST_STATE" \
  '{
    timestamp: $ts,
    since: $cursor,
    upstream: {repo: $repo, pr: $pr, discussion: $discussion},
    hasActivity: $hasActivity,
    pr: {
      comments: $prComments,
      reviews: $prReviews,
      state: $prState,
      merged: $prMerged,
      stateChanged: $stateChanged,
      previousState: $lastState,
      details: $prDetails
    },
    discussion: {
      replies: $discReplies,
      details: $discDetails
    },
    totalNew: $totalNew
  }')

echo "$RESULT"

# Update cursor and state
echo "$NOW" > "$CURSOR_FILE"
echo "$RESULT" | jq '{lastPrState: .pr.state, lastCheck: .timestamp}' > "${BASE}/upstream-check-state.json"
