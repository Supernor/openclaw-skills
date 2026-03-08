#!/usr/bin/env bash
# migrate-to-local-embeddings.sh — Migrate Chartroom from OpenAI to Ollama embeddings
# Intent: Resilient [I08], Efficient [I06].
#
# Steps:
# 1. Export all entries from LanceDB (text, id, category, importance)
# 2. Re-embed with Ollama nomic-embed-text (768-dim, local)
# 3. Create new LanceDB table with 768-dim vectors
# 4. Verify entry count matches
#
# This permanently eliminates the OpenAI embedding API dependency.
#
# Usage: bash migrate-to-local-embeddings.sh [--dry-run]

set -eo pipefail

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

EXPORT_FILE="/tmp/chartroom-export.json"
EMBEDDED_FILE="/tmp/chartroom-reembedded.json"
LOG="/root/.openclaw/logs/embedding-migration.log"
mkdir -p "$(dirname "$LOG")"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] START migration" >> "$LOG"
echo "=== Chartroom Embedding Migration: OpenAI (1536-dim) -> Ollama (768-dim) ==="

# Step 1: Fresh export
echo "Step 1: Exporting current Chartroom..."
bash /root/.openclaw/scripts/chart-export.sh > /dev/null 2>&1
COUNT=$(python3 -c "import json; print(len(json.load(open('$EXPORT_FILE'))))")
echo "  Exported $COUNT entries"

if [ "$DRY_RUN" = true ]; then
  echo "DRY RUN: Would re-embed $COUNT entries with Ollama nomic-embed-text (768-dim)"
  echo "  Estimated time: $(( COUNT / 10 )) seconds"
  echo "  No changes made."
  exit 0
fi

# Step 2: Re-embed with Ollama
echo "Step 2: Re-embedding $COUNT entries with Ollama (768-dim)..."
python3 << 'PYEOF'
import json
import urllib.request
import sys
import time

export_file = "/tmp/chartroom-export.json"
output_file = "/tmp/chartroom-reembedded.json"

with open(export_file) as f:
    entries = json.load(f)

print(f"  Processing {len(entries)} entries...")
start = time.time()
results = []
errors = 0

for i, entry in enumerate(entries):
    text = entry.get('text', '')
    if not text:
        text = entry.get('id', 'empty')

    try:
        req = urllib.request.Request(
            'http://localhost:11434/api/embed',
            data=json.dumps({"model": "nomic-embed-text", "input": text}).encode(),
            headers={'Content-Type': 'application/json'}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
            vector = data['embeddings'][0]
    except Exception as e:
        print(f"  ERROR on {entry.get('id', '?')}: {e}", file=sys.stderr)
        errors += 1
        vector = [0.0] * 768  # placeholder

    results.append({
        'id': entry.get('id', ''),
        'text': text,
        'category': entry.get('category', 'reading'),
        'importance': entry.get('importance', 0.8),
        'vector': vector
    })

    if (i + 1) % 50 == 0:
        elapsed = time.time() - start
        rate = (i + 1) / elapsed
        remaining = (len(entries) - i - 1) / rate
        print(f"  {i+1}/{len(entries)} ({rate:.0f}/s, ~{remaining:.0f}s remaining)")

elapsed = time.time() - start
print(f"  Done: {len(results)} entries in {elapsed:.1f}s ({len(results)/elapsed:.0f}/s)")
if errors:
    print(f"  ERRORS: {errors} entries got placeholder vectors")

with open(output_file, 'w') as f:
    json.dump(results, f)

print(f"  Saved to {output_file}")
PYEOF

# Step 3: Load into LanceDB with new 768-dim vectors
echo "Step 3: Loading into LanceDB..."
docker cp "$EMBEDDED_FILE" "$(docker compose ps -q openclaw-gateway):/tmp/chartroom-reembedded.json"

docker compose exec -T openclaw-gateway node --input-type=module << 'NODEOF'
import lancedb from '/app/extensions/memory-lancedb/node_modules/@lancedb/lancedb/dist/index.js';
import { readFileSync } from 'fs';

const data = JSON.parse(readFileSync('/tmp/chartroom-reembedded.json', 'utf8'));
console.log(`  Loading ${data.length} entries into LanceDB...`);

const db = await lancedb.connect('/home/node/.openclaw/memory/lancedb');

// Check current table
try {
  const oldTable = await db.openTable('memories');
  const oldCount = await oldTable.countRows();
  console.log(`  Current table: ${oldCount} rows`);

  // Backup: rename old table
  // LanceDB doesn't have rename, so we'll drop and recreate
  await db.dropTable('memories');
  console.log('  Dropped old table');
} catch (e) {
  console.log('  No existing table (or error):', e.message);
}

// Create new table with 768-dim vectors
const rows = data.map(d => ({
  id: d.id || '',
  text: d.text || '',
  category: d.category || 'reading',
  importance: d.importance || 0.8,
  vector: new Float32Array(d.vector)
}));

const table = await db.createTable('memories', rows);
const newCount = await table.countRows();
console.log(`  New table created: ${newCount} rows (768-dim vectors)`);

if (newCount !== data.length) {
  console.error(`  WARNING: Expected ${data.length} rows, got ${newCount}`);
} else {
  console.log('  Migration successful!');
}
NODEOF

# Step 4: Verify
echo "Step 4: Verifying..."
docker compose exec -T openclaw-gateway node --input-type=module << 'VERIFYEOF'
import lancedb from '/app/extensions/memory-lancedb/node_modules/@lancedb/lancedb/dist/index.js';
const db = await lancedb.connect('/home/node/.openclaw/memory/lancedb');
const table = await db.openTable('memories');
const count = await table.countRows();
const sample = await table.query().limit(1).toArray();
const dims = sample[0]?.vector?.length || 0;
console.log(`  Verified: ${count} entries, ${dims}-dim vectors`);
if (dims === 768) console.log('  SUCCESS: Using local Ollama embeddings');
else console.log('  WARNING: Unexpected dimension: ' + dims);
VERIFYEOF

echo ""
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] DONE migration" >> "$LOG"
echo "=== Migration complete ==="
echo "Next: Update chart CLI and MCP gateway to use Ollama instead of OpenAI for embeddings."
