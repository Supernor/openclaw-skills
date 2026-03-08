#!/usr/bin/env bash
# trust-refresh.sh — Check engine trust data freshness
# Intent: Trusted [I11], Observable [I17].
set -eo pipefail

LOG="/root/.openclaw/logs/trust-refresh.log"
TRUST_FILE="/root/.openclaw/engine-trust.jsonl"
mkdir -p "$(dirname "$LOG")"

if [ ! -f "$TRUST_FILE" ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] NO TRUST DATA" >> "$LOG"
  exit 0
fi

# Check last measurement timestamp per engine
python3 << 'PYEOF'
import json, sys
from datetime import datetime, timezone

trust_file = "/root/.openclaw/engine-trust.jsonl"
entries = []
with open(trust_file) as f:
    for line in f:
        if line.strip():
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue

if not entries:
    print("No trust entries found.")
    sys.exit(0)

# Find latest per engine
latest = {}
for e in entries:
    eng = e.get('engine', 'unknown')
    ts = e.get('timestamp', '')
    if eng not in latest or ts > latest[eng]:
        latest[eng] = ts

now = datetime.now(timezone.utc)
stale = []
for eng, ts in sorted(latest.items()):
    try:
        last = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        age_days = (now - last).days
        if age_days > 7:
            stale.append(f"{eng}: last measured {age_days} days ago")
    except (ValueError, TypeError):
        stale.append(f"{eng}: unparseable timestamp")

if stale:
    print(f"STALE TRUST DATA ({len(stale)} engines):")
    for s in stale:
        print(f"  {s}")
else:
    print(f"All {len(latest)} engines measured within 7 days.")
PYEOF
