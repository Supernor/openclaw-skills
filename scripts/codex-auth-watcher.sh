#!/usr/bin/env bash
# === INTENT ===
# systemd entry point for openclaw-codex-auth-watch; the logic moved to codex-auth-watcher.py (2026-10-28, #1607).
# Old bash version: codex-auth-watcher.sh.bak-guard-20261028. Do not add a retry loop here; failure must reach systemd.
export HOME=/root
exec python3 -I /root/.openclaw/scripts/codex-auth-watcher.py "$@"
