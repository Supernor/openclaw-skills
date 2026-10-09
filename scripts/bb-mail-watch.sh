#!/bin/bash
# === INTENT ===
# Launch the persistent backbone-mail watcher (python does the work; exit = Reactor wake). Pass-through args: --forever --interval N --max-hours H.
# Replaced the old 60-min count-poll (backup: /root/.openclaw/backups/bb-mail-watch.sh.pre-persistent-20261008).
exec python3 /root/.openclaw/scripts/bb-mail-watch.py "$@"
