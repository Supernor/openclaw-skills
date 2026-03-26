#!/usr/bin/env bash
# routing-audit.sh — Zero-token weekly routing quality audit
# Reads ops.db and engine_usage, writes report to Bridge-readable location.
# Ops Officer owns this. Cron: weekly Monday 9am UTC.
# Intent: Observable [I13]. Zero token cost.

set -uo pipefail

OPS_DB="/root/.openclaw/ops.db"
OUTPUT="/root/.openclaw/routing-audit-latest.md"
LOG="/root/.openclaw/logs/routing-audit.log"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

log() { echo "$NOW [routing-audit] $1" >> "$LOG"; }

cat > "$OUTPUT" << HEADER
# Routing Audit — $(date -u +"%Y-%m-%d %H:%M UTC")

## Route Success Rates (last 7 days)
HEADER

sqlite3 "$OPS_DB" -header -column "
SELECT json_extract(meta, '\$.host_op') as route,
  COUNT(*) as total,
  SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as ok,
  SUM(CASE WHEN status IN ('blocked','failed','cancelled') THEN 1 ELSE 0 END) as fail,
  ROUND(100.0 * SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) / COUNT(*)) || '%' as success
FROM tasks WHERE meta IS NOT NULL
AND json_extract(meta, '\$.host_op') IS NOT NULL
AND created_at > datetime('now', '-7 days')
GROUP BY route ORDER BY total DESC;
" >> "$OUTPUT" 2>/dev/null

cat >> "$OUTPUT" << MID

## Engine Health (last 7 days)
MID

sqlite3 "$OPS_DB" -header -column "
SELECT engine,
  COUNT(*) as calls,
  SUM(success) as ok,
  COUNT(*) - SUM(success) as fail,
  ROUND(100.0 * SUM(success) / COUNT(*)) || '%' as success,
  ROUND(AVG(duration_ms)/1000.0, 1) || 's' as avg_time
FROM engine_usage
WHERE timestamp > datetime('now', '-7 days')
GROUP BY engine ORDER BY calls DESC;
" >> "$OUTPUT" 2>/dev/null

cat >> "$OUTPUT" << MID2

## Top Failure Patterns (last 7 days)
MID2

sqlite3 "$OPS_DB" -header -column "
SELECT SUBSTR(COALESCE(errors,'') || COALESCE(outcome,''), 1, 80) as pattern,
  COUNT(*) as count
FROM tasks WHERE status IN ('blocked','failed')
AND created_at > datetime('now', '-7 days')
AND (errors IS NOT NULL AND errors != '' OR outcome LIKE '%fail%' OR outcome LIKE '%error%')
GROUP BY pattern ORDER BY count DESC LIMIT 10;
" >> "$OUTPUT" 2>/dev/null

cat >> "$OUTPUT" << MID3

## Token Waste (retry chains last 7 days)
MID3

sqlite3 "$OPS_DB" -header -column "
SELECT agent, COUNT(*) as retries,
  SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END) as wasted
FROM tasks
WHERE (task LIKE 'Fix:%' OR task LIKE 'Auto-fix:%')
AND created_at > datetime('now', '-7 days')
GROUP BY agent ORDER BY retries DESC;
" >> "$OUTPUT" 2>/dev/null

# Alerts: any route below 50% success?
BROKEN=$(sqlite3 "$OPS_DB" "
SELECT json_extract(meta, '\$.host_op')
FROM tasks WHERE meta IS NOT NULL
AND json_extract(meta, '\$.host_op') IS NOT NULL
AND created_at > datetime('now', '-7 days')
GROUP BY json_extract(meta, '\$.host_op')
HAVING ROUND(100.0 * SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) / COUNT(*)) < 50
AND COUNT(*) >= 3;
" 2>/dev/null)

if [ -n "$BROKEN" ]; then
  echo "" >> "$OUTPUT"
  echo "## ALERTS: Routes below 50% success" >> "$OUTPUT"
  echo "$BROKEN" | while read route; do
    echo "- **$route** — needs investigation" >> "$OUTPUT"
  done
  log "ALERT: broken routes: $BROKEN"
fi

echo "" >> "$OUTPUT"
echo "---" >> "$OUTPUT"
echo "Generated: $NOW (zero token cost)" >> "$OUTPUT"

log "Audit complete: $(wc -l < "$OUTPUT") lines"
echo "$NOW routing audit generated"
