#!/bin/bash
# relay-test.sh — Send a message to Relay and get a response via CLI
#
# USAGE:
#   relay-test.sh "your message here"                    # Basic message, text output
#   relay-test.sh "your message" --json                  # Full JSON response
#   relay-test.sh "your message" --deliver               # Also deliver to Telegram
#   relay-test.sh "your message" --session-key <id>          # Continue a session
#   relay-test.sh "your message" --timeout 120           # Override timeout (default: 600s = gateway limit)
#   relay-test.sh "your message" --agent spec-dev        # Talk to a different agent
#
# EXAMPLES:
#   relay-test.sh "what's your status?"                  # Quick health check
#   relay-test.sh "run system-observe full scope"        # Ask Relay to observe the system
#   relay-test.sh "dispatch a claude-code-run task to check disk space" --json
#
# OUTPUT:
#   Default: just the text response (for piping/reading)
#   --json: full JSON with runId, status, model, tokens, sessionId
#
# ERRORS:
#   Exit 1: No message provided
#   Exit 2: Gateway not reachable (container down?)
#   Exit 3: Agent returned error status
#   Exit 4: Timeout — agent took too long (increase with --timeout)
#
# NOTES:
#   - This calls openclaw agent CLI inside the gateway container
#   - Each call WITHOUT --session-key creates a NEW session (fresh context)
#   - Use --session-key to continue a conversation (preserves context)
#   - Relay runs on GPT-5.5, typical response time 10-30s
#   - Add --deliver to also send the response to Telegram

set -euo pipefail

# Cleanup trap: kill background log watcher and any docker exec we spawned
cleanup() {
    [[ -n "${LOGPID:-}" ]] && kill "$LOGPID" 2>/dev/null
    # Kill any lingering docker exec for our specific agent call
    [[ -n "${EXEC_PID:-}" ]] && kill "$EXEC_PID" 2>/dev/null
    true
}
trap cleanup EXIT INT TERM

COMPOSE="/root/openclaw/docker-compose.yml"
AGENT="relay"
TIMEOUT=600  # Match gateway's own agent timeout — let the gateway handle stall detection, not us
JSON_MODE=false
DELIVER=false
SESSION=""
MESSAGE=""
WATCH=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_MODE=true; shift ;;
        --deliver) DELIVER=true; shift ;;
        --watch) WATCH=true; shift ;;
        --session) SESSION="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --agent) AGENT="$2"; shift 2 ;;
        status)
            # Show if any agent is currently processing
            echo "Active agent processes:"
            docker compose -f "$COMPOSE" logs --tail 20 openclaw-gateway 2>/dev/null \
              | grep -v "level=warning" \
              | grep -iE "agent|session|tool_call|model" \
              | tail -10
            exit 0
            ;;
        --help|-h)
            head -30 "$0" | grep "^#" | sed 's/^# \?//'
            echo ""
            echo "  --watch    Show real-time agent activity on stderr while waiting"
            echo "  status     Show recent agent activity (no message needed)"
            exit 0
            ;;
        -*) echo "ERROR: Unknown flag '$1'. Run with --help for usage." >&2; exit 1 ;;
        *) MESSAGE="$1"; shift ;;
    esac
done

# Validate
if [[ -z "$MESSAGE" ]]; then
    echo "ERROR: No message provided." >&2
    echo "" >&2
    echo "Usage: relay-test.sh \"your message here\"" >&2
    echo "       relay-test.sh \"your message\" --json" >&2
    echo "       relay-test.sh --help" >&2
    exit 1
fi

# Check gateway is running
if ! docker compose -f "$COMPOSE" ps openclaw-gateway --format '{{.State}}' 2>/dev/null | grep -q "running"; then
    echo "ERROR: Gateway container is not running." >&2
    echo "" >&2
    echo "FIX: docker compose -f $COMPOSE up -d openclaw-gateway" >&2
    echo "THEN: wait 10s for startup, retry" >&2
    exit 2
fi

# Build command
CMD=(docker compose -f "$COMPOSE" exec -T openclaw-gateway
     openclaw agent --agent "$AGENT" --message "$MESSAGE" --timeout "$TIMEOUT")

if $JSON_MODE; then CMD+=(--json); fi
if $DELIVER; then CMD+=(--deliver); fi
if [[ -n "$SESSION" ]]; then CMD+=(--session-id "$SESSION"); fi

# Start a background log watcher so caller can see agent activity
LOGPID=""
if $WATCH || [[ "${SHOW_ACTIVITY:-0}" == "1" ]]; then
    (docker compose -f "$COMPOSE" logs --tail 0 -f openclaw-gateway 2>/dev/null \
     | grep --line-buffered -v "level=warning" \
     | grep --line-buffered -iE "agent|tool|model|relay|thinking|session" \
     | sed 's/^/  [activity] /' >&2) &
    LOGPID=$!
fi

# Execute
OUTPUT=$("${CMD[@]}" 2>&1 | grep -v "level=warning")
EXIT=$?

# Stop activity watcher
if [[ -n "$LOGPID" ]]; then kill "$LOGPID" 2>/dev/null; fi

if [[ $EXIT -ne 0 ]]; then
    echo "ERROR: Agent command failed (exit $EXIT)." >&2
    echo "" >&2
    echo "Output: $OUTPUT" >&2
    echo "" >&2
    echo "COMMON CAUSES:" >&2
    echo "  - Gateway overloaded (retry in 30s)" >&2
    echo "  - Model provider down (check: openclaw agent --agent main --message 'ping' --json)" >&2
    echo "  - Invalid agent ID (valid: relay, main, spec-dev, spec-research, etc.)" >&2
    exit 3
fi

if $JSON_MODE; then
    echo "$OUTPUT"
else
    # Extract just the text response
    TEXT=$(echo "$OUTPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    payloads = data.get('result', {}).get('payloads', [])
    for p in payloads:
        if p.get('text'):
            print(p['text'])
except:
    print(sys.stdin.read() if hasattr(sys.stdin, 'read') else '')
" 2>/dev/null)

    if [[ -z "$TEXT" ]]; then
        # Fallback: raw output if JSON parsing fails
        echo "$OUTPUT"
    else
        echo "$TEXT"
    fi
fi
