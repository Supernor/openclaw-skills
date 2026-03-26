#!/usr/bin/env bash
# bridge-nightly.sh — Nightly Bridge improvements + git backup
# Runs at 2am UTC. Finds small improvements, applies to dev, backs up to git.

set -eo pipefail
LOG="/root/.openclaw/logs/bridge-nightly.log"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Bridge nightly starting" >> "$LOG"

# --- Step 1: Git backup of Bridge dev ---
cd /root/bridge-dev
git add -A 2>/dev/null
if ! git diff --cached --quiet 2>/dev/null; then
  git commit -m "nightly: auto-commit bridge-dev changes $(date +%Y-%m-%d)" >> "$LOG" 2>&1 || true
fi

# Git backup of Bridge prod
cd /root/bridge
git add -A 2>/dev/null
if ! git diff --cached --quiet 2>/dev/null; then
  git commit -m "nightly: auto-commit bridge-prod changes $(date +%Y-%m-%d)" >> "$LOG" 2>&1 || true
fi

# --- Step 2: Check system health before making improvements ---
LOAD=$(cat /proc/loadavg | awk '{print $1}')
if (( $(echo "$LOAD > 2.0" | bc -l) )); then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Load too high ($LOAD), skipping improvements" >> "$LOG"
  exit 0
fi

# Check concurrency
IN_PROGRESS=$(sqlite3 /root/.openclaw/ops.db "SELECT COUNT(*) FROM tasks WHERE status='in_progress'")
if [ "$IN_PROGRESS" -ge 2 ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Tasks still running ($IN_PROGRESS), skipping improvements" >> "$LOG"
  exit 0
fi

# --- Step 3: Queue a Bridge improvement task ---
# Pick from a rotating list of improvements Robert would like
DAY=$(date +%u)  # 1=Mon, 7=Sun

case $DAY in
  1) IMPROVE="Review Bridge CSS for any non-GPU animations and fix them. Check all transitions use transform/opacity only." ;;
  2) IMPROVE="Add loading skeleton screens to Bridge sections that show gray placeholder shapes while data loads." ;;
  3) IMPROVE="Improve Bridge mobile touch targets — ensure all tappable elements are at least 44px." ;;
  4) IMPROVE="Add subtle micro-interactions to Bridge — status dot color transitions, smooth number counting on fleet count." ;;
  5) IMPROVE="Audit Bridge for accessibility — add aria labels, ensure color contrast meets WCAG AA." ;;
  6) IMPROVE="Optimize Bridge API response sizes — remove fields the frontend doesn't use, compress where possible." ;;
  7) IMPROVE="Review Bridge error states — what does each section show when the API is unreachable? Add graceful offline states." ;;
esac

sqlite3 /root/.openclaw/ops.db "INSERT INTO tasks (agent, urgency, status, task, context, meta) VALUES (
  'spec-dev', 'routine', 'pending',
  'Bridge nightly: $IMPROVE',
  'Nightly Bridge improvement — small, focused, one thing well. Check bridge_state before restarting.',
  '{\"host_op\": \"bridge-edit\", \"prompt\": \"$IMPROVE\", \"telegram_chat_id\": \"8561305605\"}'
)"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Queued nightly improvement (day $DAY)" >> "$LOG"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Bridge nightly complete" >> "$LOG"
