#!/bin/bash
# log-event.sh — Structured logging for Repo-Man skills
# Usage: log-event.sh <LEVEL> <SKILL> <MESSAGE> [EXIT_CODE] [STDERR]
# LEVEL: INFO|WARN|ERROR|FATAL
# Appends to local log. WARN+ appends to ERRORS.md and pushes.
set -euo pipefail

LEVEL="${1:?Usage: log-event.sh LEVEL SKILL MESSAGE [EXIT_CODE] [STDERR]}"
SKILL="${2:?}"
MESSAGE="${3:?}"
EXIT_CODE="${4:-0}"
STDERR="${5:-}"

LOCAL_LOG="/home/node/.openclaw/workspace-spec-github/logs/repo-man.log"
ERRORS_MD="/home/node/.openclaw/repos/openclaw-config/logs/ERRORS.md"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$(dirname "$LOCAL_LOG")"

# Always append to local log
cat >> "$LOCAL_LOG" << EOF
[$TIMESTAMP] $LEVEL $SKILL
Message: $MESSAGE
Exit code: $EXIT_CODE
Stderr: ${STDERR:-none}
---
EOF

# WARN+ goes to ERRORS.md and GitHub
if [ "$LEVEL" = "WARN" ] || [ "$LEVEL" = "ERROR" ] || [ "$LEVEL" = "FATAL" ]; then
  if [ -f "$ERRORS_MD" ]; then
    # Prepend new entry (latest first)
    TEMP=$(mktemp)
    cat > "$TEMP" << ENTRY
## [$TIMESTAMP] $LEVEL — $SKILL

**Message:** $MESSAGE
**Exit code:** \`$EXIT_CODE\`
$([ -n "$STDERR" ] && echo -e "**Stderr:**\n\`\`\`\n$STDERR\n\`\`\`" || echo "**Stderr:** none")

---

ENTRY
    # Remove "no errors" placeholder if present
    grep -v '^\*No errors logged yet\.\*$' "$ERRORS_MD" >> "$TEMP" 2>/dev/null || true
    mv "$TEMP" "$ERRORS_MD"

    # Push to GitHub
    cd "$(dirname "$ERRORS_MD")/.."
    git add logs/ERRORS.md
    # === INTENT: commit if there are staged changes, then push; report push
    # failures loudly instead of swallowing them via `|| true` ===
    if ! git diff --cached --quiet; then
      if git commit -q -m "[log] $LEVEL $SKILL $(date -u +%Y-%m-%d)"; then
        if ! git push -q origin main 2>/tmp/log-event-push-err.$$; then
          echo "log-event.sh: git push origin main FAILED for openclaw-config (skill=$SKILL, level=$LEVEL)." >&2
          echo "  HISTORY: pushes were silently swallowed by '|| true' since 2026-06-24, fixed 2026-07-07." >&2
          echo "  WHAT HASN'T BEEN TRIED: check remote auth (git ls-remote), check for diverged branch (git pull --rebase)." >&2
          echo "  WHAT WORKED BEFORE: none recorded yet for this exact failure — this is a new diagnostic path." >&2
          echo "  Push stderr:" >&2
          cat /tmp/log-event-push-err.$$ >&2
          rm -f /tmp/log-event-push-err.$$
        else
          rm -f /tmp/log-event-push-err.$$
        fi
      else
        echo "log-event.sh: git commit failed for openclaw-config ERRORS.md (skill=$SKILL, level=$LEVEL)." >&2
      fi
    fi
  fi
fi

echo '{"logged":true,"level":"'"$LEVEL"'","skill":"'"$SKILL"'","timestamp":"'"$TIMESTAMP"'"}'
