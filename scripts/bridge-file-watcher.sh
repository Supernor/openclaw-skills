#!/usr/bin/env bash
# bridge-file-watcher.sh — Auto-commit bridge-dev changes on file modification.
# Uses inotifywait (zero CPU when idle). Debounces: waits 10s after last change
# before committing, so rapid edits batch into one commit.
#
# WHY THIS EXISTS: bridge-edit agents can overwrite each other's work between
# nightly git backups. This watcher ensures every file change is captured in git
# within seconds, not hours. See chart: bridge-version-safety.
#
# Watched files: app.js, index.html, style.css, dashboard-api.py
# Runs as: systemd service (openclaw-bridge-watcher.service)

set -eo pipefail

BRIDGE_DIR="/root/bridge-dev"
WATCHED_FILES="app.js|index.html|style.css|dashboard-api.py"
DEBOUNCE_SEC=10
LOG="/root/.openclaw/logs/bridge-watcher.log"

cd "$BRIDGE_DIR"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >> "$LOG"; }
log "Bridge file watcher started"

commit_if_dirty() {
    cd "$BRIDGE_DIR"
    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        return  # nothing to commit
    fi
    git add -A 2>/dev/null
    local changed
    changed=$(git diff --cached --name-only 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    if [ -n "$changed" ]; then
        git commit -m "auto: file change detected — $changed" >> "$LOG" 2>&1 || true
        log "Auto-committed: $changed"
    fi
}

# Main loop: inotifywait blocks until a watched file is modified.
# After detecting a change, wait DEBOUNCE_SEC for rapid edits to settle.
while true; do
    inotifywait --quiet --event close_write,moved_to \
        --include "$WATCHED_FILES" \
        "$BRIDGE_DIR" 2>/dev/null

    # Debounce: wait for edits to settle
    sleep "$DEBOUNCE_SEC"

    # Drain any queued events during debounce
    while inotifywait --quiet --timeout 2 --event close_write,moved_to \
        --include "$WATCHED_FILES" \
        "$BRIDGE_DIR" 2>/dev/null; do
        sleep 2
    done

    commit_if_dirty
done
