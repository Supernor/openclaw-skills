#!/bin/bash
# SHIM: gemini-task → engine.py translation layer
# Logs usage for migration tracking, translates old arguments, forwards to engine.py
# Old tool: /usr/local/bin/gemini-task (bash → gemini CLI, 9-29s overhead)
# New tool: /root/.openclaw/scripts/engine.py (direct API, 0.7-10s)
# Created: 2026-05-08 during Month of May Automation Audit

SHIM_LOG="/root/.openclaw/logs/shim-usage.log"
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) SHIM:gemini-task caller=$(ps -o comm= $PPID 2>/dev/null || echo unknown) args: ${*:0:120}" >> "$SHIM_LOG"

# Parse old arguments and translate to engine.py
PROMPT=""
MODE="quick"  # default for gemini
TIMEOUT=""
TASK_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --no-mcp) shift ;;           # Drop: direct API doesn't use MCP
    --with-mcp) shift ;;         # Drop: direct API doesn't use MCP
    --no-failover) shift ;;      # Drop: translation layer handles routing
    --model) shift 2 ;;          # Drop: translation layer selects model
    --dir) CWD="$2"; shift 2 ;;  # Forward as --cwd for analyze mode
    --json) shift ;;             # Drop: use classify() for JSON
    --project) shift 2 ;;        # Drop: logged internally
    --task-id) TASK_ID="$2"; shift 2 ;;
    *) PROMPT="$1"; shift ;;
  esac
done

if [ -z "$PROMPT" ]; then
  echo "Usage: gemini-task \"prompt\" [--timeout N]" >&2
  exit 1
fi

# Detect mode from context
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')
if echo "$PROMPT_LOWER" | grep -qE "search|latest|current|news|version|web"; then
  MODE="search"
elif echo "$PROMPT_LOWER" | grep -qE "score|review|analyze|audit|compare"; then
  MODE="analyze"
fi

# Build engine.py command
CMD=(python3 /root/.openclaw/scripts/engine.py "$MODE" "$PROMPT")
[ -n "$TIMEOUT" ] && CMD+=(--timeout "$TIMEOUT")
[ -n "$TASK_ID" ] && CMD+=(--task-id "$TASK_ID")
[ -n "$CWD" ] && CMD+=(--cwd "$CWD")

exec "${CMD[@]}"
