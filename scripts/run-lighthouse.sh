#!/usr/bin/env bash
# run-lighthouse.sh — Run Lighthouse CI against a URL and report scores.
# Used after preview deploys to verify quality before Robert reviews.
#
# Usage: run-lighthouse.sh <url> [project-id]
# Returns: JSON with performance, accessibility, best-practices, seo scores.

set -eo pipefail

URL="${1:?Usage: run-lighthouse.sh URL [PROJECT_ID]}"
PROJECT_ID="${2:-}"

# Check if lighthouse is available
if ! which lighthouse >/dev/null 2>&1; then
    # Try npx
    if ! npx lighthouse --version >/dev/null 2>&1; then
        echo '{"error": "lighthouse not installed. Run: npm i -g lighthouse"}'
        exit 1
    fi
    LH="npx lighthouse"
else
    LH="lighthouse"
fi

# Run lighthouse in headless chrome
REPORT=$($LH "$URL" \
    --output=json \
    --quiet \
    --chrome-flags="--headless --no-sandbox --disable-gpu" \
    --only-categories=performance,accessibility,best-practices,seo \
    2>/dev/null)

if [ -z "$REPORT" ]; then
    echo '{"error": "lighthouse returned empty report"}'
    exit 1
fi

# Extract scores
SCORES=$(echo "$REPORT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    cats = d.get('categories', {})
    scores = {
        'performance': int((cats.get('performance', {}).get('score', 0) or 0) * 100),
        'accessibility': int((cats.get('accessibility', {}).get('score', 0) or 0) * 100),
        'best_practices': int((cats.get('best-practices', {}).get('score', 0) or 0) * 100),
        'seo': int((cats.get('seo', {}).get('score', 0) or 0) * 100),
    }
    scores['pass'] = all(v >= 90 for v in scores.values())
    print(json.dumps(scores))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)

echo "$SCORES"

# Log to alignment metrics if project_id provided
if [ -n "$PROJECT_ID" ] && [ -n "$SCORES" ]; then
    sqlite3 /root/.openclaw/ops.db "
        INSERT INTO alignment_metrics (project_id, phase, event, detail)
        VALUES ('$PROJECT_ID', 'quality', 'lighthouse_check', '$(echo "$SCORES" | tr "'" "_")')
    " 2>/dev/null
fi
