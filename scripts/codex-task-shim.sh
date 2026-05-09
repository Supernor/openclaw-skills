#!/bin/bash
# SHIM: codex-task → engine.py translation layer
# Logs usage for migration tracking, translates old arguments, forwards to engine.py
# Old tool: /usr/local/bin/codex-task (bash → npx codex, preamble injection, 17s+)
# New tool: /root/.openclaw/scripts/engine.py code mode (direct npx, pool rotation, 8-15s)
# Backup: /usr/local/bin/codex-task.bak-20260508
#
# Maps to Google SRE "Error Budgets" concept (Ch.3) — this shim adds
# pool rotation, failover, flock serialization, and quota detection.

SHIM_LOG="/root/.openclaw/logs/shim-usage.log"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) SHIM:codex-task caller=$(ps -o comm= $PPID 2>/dev/null || echo unknown) args: ${*:0:120}" >> "$SHIM_LOG"

# Parse old arguments and translate to engine.py
PROMPT=""
MODE="code"
TIMEOUT=""
TASK_ID=""
CWD=""

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --dir) CWD="$2"; shift 2 ;;
    --task-id) TASK_ID="$2"; shift 2 ;;
    --no-failover) shift ;;      # Drop: engine.py handles failover internally
    --full-auto) shift ;;        # Drop: engine.py always uses bypass-approvals
    --model) shift 2 ;;          # Drop: engine.py selects model internally
    --json) shift ;;             # Drop: raw output by default
    --project) shift 2 ;;        # Drop: logged internally
    *) PROMPT="$1"; shift ;;
  esac
done

if [ -z "$PROMPT" ]; then
  echo "Usage: codex-task \"prompt\" [--timeout N] [--dir /path]" >&2
  exit 1
fi

# Detect if this is analytical (not code) — route to analyze instead
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
if echo "$PROMPT_LOWER" | grep -qE "^(score|review|analyze|compare|summarize|assess|audit)" && \
   ! echo "$PROMPT_LOWER" | grep -qE "(edit|fix|create|write|patch|refactor|file|script)"; then
  MODE="analyze"
fi

# Build engine.py command
CMD=(python3 /root/.openclaw/scripts/engine.py "$MODE" "$PROMPT")
[ -n "$TIMEOUT" ] && CMD+=(--timeout "$TIMEOUT")
[ -n "$TASK_ID" ] && CMD+=(--task-id "$TASK_ID")
[ -n "$CWD" ] && CMD+=(--cwd "$CWD")

exec "${CMD[@]}"
