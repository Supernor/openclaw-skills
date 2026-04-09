#!/usr/bin/env bash
# trust-refresh.sh — Check engine trust data freshness
# Intent: Trusted [I11], Observable [I17].
set -eo pipefail

LOG="/root/.openclaw/logs/trust-refresh.log"
TRUST_FILE="/root/.openclaw/engine-trust.jsonl"
JSON_MODE=false

for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=true ;;
  esac
done

mkdir -p "$(dirname "$LOG")"

if [ ! -f "$TRUST_FILE" ]; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] NO TRUST DATA" >> "$LOG"
  if [ "$JSON_MODE" = true ]; then
    python3 -c "import json; print(json.dumps({'status':'fail','message':'No trust data file','suggestion':'run: engine-log to begin trust data collection'}, indent=2))"
  fi
  exit 0
fi

# Check last measurement timestamp per engine
python3 - "$JSON_MODE" << 'PYEOF'
import json, sys
from datetime import datetime, timezone

json_mode = sys.argv[1] == "true" if len(sys.argv) > 1 else False
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
    if json_mode:
        print(json.dumps({'status': 'fail', 'message': 'No trust entries found', 'suggestion': 'run: engine-log to record engine measurements'}, indent=2))
    else:
        print("No trust entries found.")
    sys.exit(0)

# Aggregate by engine so JSON output can flag stale data and low trust.
latest = {}
scores = {}
for e in entries:
    eng = e.get('engine', 'unknown')
    ts = e.get('timestamp', '')
    if eng not in latest or ts > latest[eng]:
        latest[eng] = ts
    try:
        scores.setdefault(eng, []).append(float(e.get('accuracy', 0)))
    except (TypeError, ValueError):
        pass

now = datetime.now(timezone.utc)
checks = []
for eng, ts in sorted(latest.items()):
    try:
        last = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        age_days = (now - last).days
        is_stale = age_days > 7
        trust_score = round((sum(scores.get(eng, [])) / len(scores[eng])) / 10, 3) if scores.get(eng) else None
        check = {
            'engine': eng,
            'last_measured': ts,
            'age_days': age_days,
            'status': 'stale' if is_stale else 'ok'
        }
        if is_stale:
            check['suggestion'] = 'Run trust-refresh.sh to update measurements'
        elif trust_score is not None and trust_score < 0.5:
            check['suggestion'] = f'Run engine-trust-report for details on {eng}'
        checks.append(check)
    except (ValueError, TypeError):
        checks.append({
            'engine': eng,
            'last_measured': ts,
            'status': 'error',
            'suggestion': f'run: engine-trust-report {eng} — timestamp unparseable, re-measure'
        })

stale = [c for c in checks if c['status'] != 'ok']

if json_mode:
    result = {
        'timestamp': now.strftime('%Y-%m-%dT%H:%M:%SZ'),
        'total_engines': len(checks),
        'stale': len(stale),
        'status': 'fail' if stale else 'pass',
        'engines': checks
    }
    print(json.dumps(result, indent=2))
else:
    if stale:
        print(f"STALE TRUST DATA ({len(stale)} engines):")
        for c in stale:
            print(f"  {c['engine']}: last measured {c.get('age_days', '?')} days ago")
    else:
        print(f"All {len(checks)} engines measured within 7 days.")
PYEOF
