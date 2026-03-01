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
ERRORS_MD="/home/node/.openclaw/workspace-spec-github/openclaw-config/logs/ERRORS.md"
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
    git diff --cached --quiet || git commit -q -m "[log] $LEVEL $SKILL $(date -u +%Y-%m-%d)" && git push -q origin main 2>/dev/null || true
  fi
fi

echo '{"logged":true,"level":"'"$LEVEL"'","skill":"'"$SKILL"'","timestamp":"'"$TIMESTAMP"'"}'
