#!/bin/bash
# === INTENT ===
# One-command rollback of the 2026-10-14 Bridge HTTPS front-door change: restores the 8 pre-change files from /root/.openclaw/backups (stamp 20261014T115401), then restarts Bridge (back on 0.0.0.0) and the Caddy front door.
# Usage: bridge-https-rollback.sh [--dry-run]. DNS records bridge/lounge.knownself.ai are left in place (harmless without a Caddy site). Refuses to restart while an ops.db task is in_progress unless FORCE=1.
# === END ===
set -u
STAMP=20261014T115401
B=/root/.openclaw/backups
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
run() { if [ $DRY = 1 ]; then echo "DRY-RUN would: $*"; else echo "+ $*"; "$@" || { echo "FAILED: $*" >&2; exit 1; }; fi; }
restore() { run cp -p "$B/$1.pre-https-$STAMP" "$2"; }
for f in dashboard-api.py openclaw-bridge-dev.service mcp-front.Caddyfile tap_login_bridge.py tap_login_bridge.lab.py morning-briefing.sh heartbeat-probe.py stitch-mockup.sh; do [ -f "$B/$f.pre-https-$STAMP" ] || { echo "MISSING backup $f" >&2; exit 2; }; done
restore dashboard-api.py /root/bridge-dev/dashboard-api.py
restore openclaw-bridge-dev.service /etc/systemd/system/openclaw-bridge-dev.service
restore mcp-front.Caddyfile /srv/knownself-public/config/mcp-front.Caddyfile
restore tap_login_bridge.py /usr/local/lib/braindump-login/tap_login_bridge.py
restore tap_login_bridge.lab.py /root/.openclaw/dev/tap-login/tap_login_bridge.py
restore morning-briefing.sh /root/.openclaw/scripts/morning-briefing.sh
restore heartbeat-probe.py /root/.openclaw/scripts/heartbeat-probe.py
restore stitch-mockup.sh /root/.openclaw/scripts/stitch-mockup.sh
BUSY=$(python3 -c "import sqlite3;c=sqlite3.connect('file:/root/.openclaw/ops.db?mode=ro',uri=True);print(c.execute(\"select count(*) from tasks where status='in_progress'\").fetchone()[0])" 2>/dev/null || echo "?")
echo "ops.db tasks in_progress: $BUSY"
if [ "$BUSY" != "0" ] && [ "${FORCE:-0}" != "1" ] && [ $DRY = 0 ]; then echo "Files restored. NOT restarting: tasks in progress (or check failed). When clear: FORCE=1 $0" >&2; exit 3; fi
run systemctl daemon-reload
run systemctl restart openclaw-bridge-dev
run systemctl restart knownself-mcp-front
[ $DRY = 1 ] && echo "(dry run: nothing changed)" || echo "Rolled back. Bridge is on http://187.77.193.174:8082 again (DNS bridge/lounge.knownself.ai left in place)."
