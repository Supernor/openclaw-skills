#!/usr/bin/env bash
# codex-auth-watcher.sh — Event-driven Codex auth sync.
#
# Watches ~/.codex/auth.json for modifications using inotifywait (not polling).
# When the file changes (e.g., after `codex login`), automatically syncs
# the new tokens to the gateway via fix-codex-auth.sh.
#
# NOTE FOR AGENTS: This runs as a systemd service (openclaw-codex-auth-watch).
# You don't need to run this manually. If Codex auth is broken, use
# fix-codex-auth.sh instead — it auto-detects and fixes.
#
#   fix-codex-auth.sh         <- manual fix (start here)
#   codex-auth-watcher.sh     <- you are here (auto-watches, runs as service)
#   sync-codex-auth.sh        <- sync-only step (called by fix-codex-auth.sh)
#
# Managed by: systemctl {start|stop|status|restart} openclaw-codex-auth-watch

# NOTE: no set -eo pipefail — this is a daemon loop, we handle errors explicitly.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="/root/.openclaw/logs/codex-auth-watcher.log"

# Resolve auth file path — explicit fallback, never allow /.codex/auth.json
if [ -f "/root/.codex/auth.json" ]; then
    AUTH_FILE="/root/.codex/auth.json"
elif [ -n "$HOME" ] && [ -f "$HOME/.codex/auth.json" ] && [ "$HOME" != "/" ]; then
    AUTH_FILE="$HOME/.codex/auth.json"
else
    AUTH_FILE="/root/.codex/auth.json"
fi

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOG"; }

log "codex-auth-watcher started"
log "Resolved AUTH_FILE=$AUTH_FILE"

# Verify path is safe (guardrail: no /.codex/auth.json)
case "$AUTH_FILE" in
    /.codex/*)
        log "ERROR: AUTH_FILE resolved to /.codex/ (root of filesystem)"
        log "WHY: HOME is unset or set to '/'. systemd services may not inherit HOME."
        log "DO THIS: Set Environment=HOME=/root in the systemd unit, or hardcode AUTH_FILE=/root/.codex/auth.json"
        log "VERIFY: systemctl show openclaw-codex-auth-watch -p Environment"
        exit 1
        ;;
esac

if [ ! -f "$AUTH_FILE" ]; then
    log "WARNING: $AUTH_FILE does not exist yet — will wait for creation"
    log "DO THIS: Run 'codex login' to create the auth file, then this watcher will detect it."
fi

while true; do
    # Wait for file modification. --timeout 300 re-establishes watch every 5 min
    # (handles file deletion/recreation). Exit code 2 = timeout (normal, loop again).
    inotifywait -e modify,create,attrib,move_self --timeout 300 "$AUTH_FILE" 2>>"$LOG"
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        # File was modified
        log "auth.json changed — waiting 2s for file to settle"
        sleep 2
        log "running fix-codex-auth.sh"
        "$SCRIPT_DIR/fix-codex-auth.sh" >> "$LOG" 2>&1 || {
            log "fix-codex-auth.sh failed — will retry on next file change"
        }
    elif [ $EXIT_CODE -eq 2 ]; then
        # Timeout — normal, just re-establish watch
        :
    else
        log "inotifywait exited with code $EXIT_CODE — retrying in 10s"
        sleep 10
    fi
done
