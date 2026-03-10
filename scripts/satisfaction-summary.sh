#!/usr/bin/env bash
# satisfaction-summary.sh — One-line satisfaction summary for sitrep inclusion.
# Intent: Observable [I13]. Owner: Captain.

set -eo pipefail

LINE=$(chart search "satisfaction report" 2>/dev/null | head -1 || echo "")

if [ -z "$LINE" ] || ! echo "$LINE" | grep -q "Fleet avg"; then
  echo "Satisfaction: No report available."
  exit 0
fi

FLEET_AVG=$(echo "$LINE" | grep -oP 'Fleet avg \K[0-9.]+' || echo "?")
BOTTOM=$(echo "$LINE" | grep -oP 'Bottom: \K[^.]+' || echo "?")
ALERTS=$(echo "$LINE" | grep -oP 'ALERTS: \K[^.]+' || echo "none")
DATE=$(echo "$LINE" | grep -oP 'Verified: \K[0-9-]+' || echo "?")

echo "Satisfaction: Fleet ${FLEET_AVG}/10. Bottom: ${BOTTOM}. Alerts: ${ALERTS}. As of ${DATE}."
