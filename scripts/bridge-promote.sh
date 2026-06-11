#!/usr/bin/env bash
# bridge-promote.sh — Promote Bridge dev to production after verification
set -eo pipefail

# === GUARD (2026-06-10, Robert directive): /root/bridge is the PRESERVED OLD ===
# === BRIDGE — his rollback target if he dislikes the new one. Promoting      ===
# === OVERWRITES it. Also: this script restarts a wrong/disabled service      ===
# === (scar danger; chart issue-bridge-promote-stale-service-20260601).       ===
if [ "${BRIDGE_PROMOTE_CONFIRM:-}" != "yes" ]; then
  echo "BLOCKED: /root/bridge is the preserved OLD Bridge (rollback target — Robert 2026-06-10)."
  echo "Running this would OVERWRITE it with dev files and restart a stale service."
  echo "Swap/rollback procedure: chart read procedure-bridge-rollback-20260610"
  echo "If promotion is REALLY intended: BRIDGE_PROMOTE_CONFIRM=yes bash $0"
  exit 1
fi

echo "Checking Bridge dev health..."
HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8083/api/health)
if [ "$HTTP" != "200" ]; then
  echo "ABORT: Bridge dev is not healthy (HTTP $HTTP). Fix dev first."
  exit 1
fi

echo "Dev is healthy. Promoting to prod..."
cp /root/bridge-dev/index.html /root/bridge/index.html
cp /root/bridge-dev/style.css /root/bridge/style.css
cp /root/bridge-dev/app.js /root/bridge/app.js
cp /root/bridge-dev/sw.js /root/bridge/sw.js
cp /root/bridge-dev/dashboard-api.py /root/bridge/dashboard-api.py
# Keep prod port
sed -i 's/port=8083/port=8082/' /root/bridge/dashboard-api.py

# Bump SW cache version so browsers detect the new deploy
TIMESTAMP=$(date +%s)
sed -i "s/const CACHE_VERSION = .*/const CACHE_VERSION = ${TIMESTAMP};/" /root/bridge/sw.js

# Kill any stale process on prod port before restart
fuser -k 8082/tcp 2>/dev/null || true
sleep 2

# Restart prod Bridge via systemd
systemctl restart openclaw-bridge

# Wait and verify
sleep 5
if systemctl is-active openclaw-bridge >/dev/null 2>&1; then
  PROD_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8082/api/health)
  if [ "$PROD_HTTP" = "200" ]; then
    echo "Promoted and verified. Prod Bridge healthy on :8082."
  else
    echo "WARNING: Prod Bridge running but health check returned HTTP $PROD_HTTP."
  fi
else
  echo "ERROR: Prod Bridge failed to start after promote. Check: systemctl status openclaw-bridge"
fi
