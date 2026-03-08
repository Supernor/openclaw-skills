#!/usr/bin/env bash
# chart-export.sh — Dump Chartroom to JSON for CLIs without MCP access
# Intent: Informed [I18], Efficient [I06]. Purpose: [P-TBD].
#
# Exports all Chartroom entries to /tmp/chartroom-export.json
# Codex/Gemini read this file instead of burning tokens on MCP searches.
# Run via cron every 6h or on-demand.

set -eo pipefail

OUT="/tmp/chartroom-export.json"
COMPACT_OUT="/tmp/chartroom-compact.json"
LOG="/root/.openclaw/logs/chart-export.log"
mkdir -p "$(dirname "$LOG")"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START chart-export" >> "$LOG"

# Use the container's LanceDB directly to avoid MCP overhead
docker compose exec -T openclaw-gateway node -e "
const lancedb = require('/home/node/.openclaw/mcp-servers/openclaw-gateway/node_modules/@lancedb/lancedb');
(async () => {
  const db = await lancedb.connect('/home/node/.openclaw/memory/lancedb');
  const table = await db.openTable('memories');
  const rows = await table.query().limit(1000).toArray();
  const entries = rows.map(r => ({
    id: r.id,
    text: r.text,
    category: r.category,
    importance: r.importance
  }));
  console.log(JSON.stringify(entries));
})();
" 2>/dev/null > "$OUT"

COUNT=$(python3 -c "import json; print(len(json.load(open('$OUT'))))" 2>/dev/null || echo 0)

# Also create compact version (IDs + category + first 120 chars)
python3 -c "
import json
data = json.load(open('$OUT'))
compact = [{'id': e['id'], 'cat': e['category'], 'text': e['text'][:120]} for e in data]
json.dump(compact, open('$COMPACT_OUT', 'w'))
print(f'{len(compact)} entries exported')
" 2>/dev/null

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DONE: $COUNT entries -> $OUT + $COMPACT_OUT" >> "$LOG"
echo "$COUNT entries exported to $OUT (full) and $COMPACT_OUT (compact)"
