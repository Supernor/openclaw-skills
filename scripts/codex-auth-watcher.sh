#!/usr/bin/env bash
# codex-auth-watcher.sh — Event-driven Codex auth sync.
#
# [2026-10-07: now watches pool-a AND pool-b and calls sync-openai-token.sh — see loop below]
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

# 2026-10-07 REAUTH-FIX (deferred #251): watches BOTH pools' auth files and calls sync-openai-token.sh
# (live sqlite-store sync + change-detected gateway restart) instead of the dead fix-codex-auth.sh ->
# sync-codex-auth.sh chain. Every 5-min inotify timeout also retries a busy-blocked pending restart.
POOL_B_FILE="/root/.codex-pool-b/auth.json"
WATCH_FILES=("$AUTH_FILE")
[ -f "$POOL_B_FILE" ] && WATCH_FILES+=("$POOL_B_FILE")
log "Watching: ${WATCH_FILES[*]}"

sync_for() {   # $1 = changed file
    case "$1" in
        "$POOL_B_FILE") OPENAI_SYNC_HOST_AUTH="$POOL_B_FILE" OPENAI_SYNC_PROFILE=openai:pool-b "$SCRIPT_DIR/sync-openai-token.sh" >> "$LOG" 2>&1 ;;
        *)              "$SCRIPT_DIR/sync-openai-token.sh" >> "$LOG" 2>&1 ;;
    esac
}

while true; do
    # --format '%w' prints the watched file that fired. Exit 2 = timeout (normal, loop again).
    CHANGED=$(inotifywait -e modify,create,attrib,move_self --timeout 300 --format '%w' "${WATCH_FILES[@]}" 2>>"$LOG")
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        log "auth file changed: $CHANGED — waiting 2s for file to settle"
        sleep 2
        log "running sync-openai-token.sh for $CHANGED"
        sync_for "$CHANGED" || log "sync-openai-token.sh failed for $CHANGED — see sync-openai-token.log; will retry on next file change"
    elif [ $EXIT_CODE -eq 2 ]; then
        # Timeout — re-establish watch (picks up recreated files) and retry any busy-deferred restart.
        if [ -f /root/.openclaw/state/openai-sync/restart-pending ]; then
            log "restart pending — retrying"
            OPENAI_SYNC_RESTART_ONLY=1 "$SCRIPT_DIR/sync-openai-token.sh" >> "$LOG" 2>&1 || true
        fi
        [ ${#WATCH_FILES[@]} -lt 2 ] && [ -f "$POOL_B_FILE" ] && WATCH_FILES+=("$POOL_B_FILE")
    else
        log "inotifywait exited with code $EXIT_CODE — retrying in 10s"
        sleep 10
    fi
done
