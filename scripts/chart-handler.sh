#!/usr/bin/env bash
# chart-handler.sh — Container-side /chart command handler
# Runs INSIDE the OpenClaw container (unlike /usr/local/bin/chart which uses docker compose exec).
# Called by Relay or any agent when a user types /chart in Discord.
#
# Usage:
#   chart-handler.sh search <keywords>
#   chart-handler.sh read <id>
#   chart-handler.sh add <id> <text> [category] [importance]
#   chart-handler.sh update <id> <new-text> [category] [importance]
#   chart-handler.sh list [limit]
#   chart-handler.sh stale
#   chart-handler.sh help
#
# Intent: Informed [I18]. Purpose: [P-TBD].

set -eo pipefail

LDB_PATH="/home/node/.openclaw/memory/lancedb"
LDB_MOD="/app/extensions/memory-lancedb/node_modules/@lancedb/lancedb/dist/index.js"
OPENAI_MOD="/app/extensions/memory-lancedb/node_modules/openai/index.mjs"

# Fallback paths for host execution
if [ ! -d "/app/extensions" ] && [ -d "/root/.openclaw" ]; then
  echo '{"error":"This script runs inside the container. Use /usr/local/bin/chart on the host."}'
  exit 1
fi

CMD="${1:-help}"
shift 2>/dev/null || true

cmd_search() {
  local keywords="$1"
  if [ -z "$keywords" ]; then
    echo "Usage: /chart search <keywords>"
    exit 1
  fi
  openclaw ltm search "$keywords" 2>/dev/null | grep -v "level=warning" | grep -v "plugin registered"
}

cmd_read() {
  local id="$1"
  if [ -z "$id" ]; then
    echo "Usage: /chart read <id>"
    exit 1
  fi
  node --input-type=module <<SCRIPT
import lancedb from '${LDB_MOD}';
const db = await lancedb.connect('${LDB_PATH}');
const table = await db.openTable('memories');
const rows = await table.query().where("id = '${id}'").limit(1).toArray();
if (rows.length === 0) { console.log('Not found: ${id}'); process.exit(1); }
const r = rows[0];
console.log('**' + r.id + '** [' + (r.category || 'unset') + '] importance: ' + (r.importance || 0));
console.log('');
console.log(r.text || '(empty)');
SCRIPT
}

cmd_add() {
  local id="$1" text="$2" category="${3:-reading}" importance="${4:-0.8}"
  if [ -z "$id" ] || [ -z "$text" ]; then
    echo "Usage: /chart add <id> \"<text>\" [category] [importance]"
    exit 1
  fi
  node --input-type=module <<SCRIPT
import lancedb from '${LDB_MOD}';
import OpenAI from '${OPENAI_MOD}';
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
const db = await lancedb.connect('${LDB_PATH}');
const table = await db.openTable('memories');
const sample = await table.query().limit(1).toArray();
const fields = Object.keys(sample[0]);
const e = {};
for (const f of fields) e[f] = null;
e.id = $(jq -n --arg v "$id" '$v');
e.text = $(jq -n --arg v "$text" '$v');
e.category = $(jq -n --arg v "$category" '$v');
e.importance = $importance;
const resp = await openai.embeddings.create({ model: 'text-embedding-3-small', input: e.text });
e.vector = resp.data[0].embedding;
await table.add([e]);
console.log('Charted: ' + e.id + ' [' + e.category + '] importance=' + e.importance);
SCRIPT
}

cmd_update() {
  local id="$1" text="$2" category="${3:-}" importance="${4:-}"
  if [ -z "$id" ] || [ -z "$text" ]; then
    echo "Usage: /chart update <id> \"<new-text>\" [category] [importance]"
    exit 1
  fi

  # Auto-stamp Verified date
  local today
  today=$(date -u +%Y-%m-%d)
  if ! echo "$text" | grep -q "Verified:"; then
    text="${text} Verified: ${today}."
  fi

  # Read existing to preserve category/importance if not specified
  if [ -z "$category" ] || [ -z "$importance" ]; then
    local existing
    existing=$(node --input-type=module <<SCRIPT
import lancedb from '${LDB_MOD}';
const db = await lancedb.connect('${LDB_PATH}');
const table = await db.openTable('memories');
const rows = await table.query().where("id = '${id}'").limit(1).toArray();
if (rows.length > 0) {
  console.log(JSON.stringify({category: rows[0].category || 'reading', importance: rows[0].importance || 0.8}));
} else {
  console.log(JSON.stringify({category: 'reading', importance: 0.8}));
}
SCRIPT
    ) || true
    [ -z "$category" ] && category=$(echo "$existing" | jq -r '.category // "reading"' 2>/dev/null || echo "reading")
    [ -z "$importance" ] && importance=$(echo "$existing" | jq -r '.importance // 0.8' 2>/dev/null || echo "0.8")
  fi

  # Delete old entry
  node --input-type=module <<SCRIPT 2>/dev/null || true
import lancedb from '${LDB_MOD}';
const db = await lancedb.connect('${LDB_PATH}');
const table = await db.openTable('memories');
await table.delete('id = "${id}"');
SCRIPT

  # Add updated entry
  cmd_add "$id" "$text" "$category" "$importance"
  echo "(updated with Verified: ${today})"
}

cmd_list() {
  local limit="${1:-20}"
  node --input-type=module <<SCRIPT
import lancedb from '${LDB_MOD}';
const db = await lancedb.connect('${LDB_PATH}');
const table = await db.openTable('memories');
const all = await table.query().limit(${limit}).toArray();
for (const r of all) {
  const cat = (r.category || 'unset').padEnd(12);
  const imp = (r.importance || 0).toFixed(1);
  const preview = (r.text || '').substring(0, 80).replace(/\n/g, ' ');
  console.log(cat + ' ' + imp + '  ' + r.id + '  ' + preview + '...');
}
console.log('');
console.log('Total: ' + all.length + ' entries (showing up to ${limit})');
SCRIPT
}

cmd_stale() {
  local today_epoch
  today_epoch=$(date -u +%s)

  echo "Scanning Chartroom for stale entries..."

  local entries
  entries=$(node --input-type=module <<SCRIPT
import lancedb from '${LDB_MOD}';
const db = await lancedb.connect('${LDB_PATH}');
const table = await db.openTable('memories');
const all = await table.query().limit(500).toArray();
for (const r of all) {
  const cat = r.category || 'reading';
  const text = (r.text || '').replace(/\n/g, ' ');
  console.log(JSON.stringify({id: r.id, category: cat, text: text}));
}
SCRIPT
  ) || true

  if [ -z "$entries" ]; then
    echo "No entries found."
    return
  fi

  local stale_count=0

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local eid ecat etext
    eid=$(echo "$line" | jq -r '.id' 2>/dev/null) || continue
    ecat=$(echo "$line" | jq -r '.category' 2>/dev/null) || true
    etext=$(echo "$line" | jq -r '.text' 2>/dev/null) || true

    local max_days=30
    case "$ecat" in
      model*|profile*) max_days=7 ;;
      architecture*) max_days=30 ;;
      vision*) continue ;;
      issue*|error*) max_days=14 ;;
    esac
    local id_prefix="${eid%%-*}"
    case "$id_prefix" in
      model|profile) [ 7 -lt "$max_days" ] && max_days=7 ;;
      vision) continue ;;
      issue|error) [ 14 -lt "$max_days" ] && max_days=14 ;;
    esac

    local verified_date
    verified_date=$(echo "$etext" | grep -oP 'Verified:\s*\K\d{4}-\d{2}-\d{2}' | tail -1) || true

    if [ -z "$verified_date" ]; then
      printf "  STALE  %-40s [%s] no Verified date\n" "$eid" "$ecat"
      stale_count=$((stale_count + 1))
      continue
    fi

    local ver_epoch
    ver_epoch=$(date -d "$verified_date" +%s 2>/dev/null) || continue
    local age_days=$(( (today_epoch - ver_epoch) / 86400 ))

    if [ "$age_days" -gt "$max_days" ]; then
      printf "  STALE  %-40s [%s] verified %s (%dd ago, threshold %dd)\n" "$eid" "$ecat" "$verified_date" "$age_days" "$max_days"
      stale_count=$((stale_count + 1))
    fi
  done <<< "$entries"

  echo ""
  echo "Found $stale_count stale entries."
}

cmd_help() {
  cat <<'HELP'
**/chart** — Chartroom commands

`/chart search <keywords>` — Semantic search
`/chart read <id>` — Read a specific chart
`/chart add <id> "<text>" [category] [importance]` — Add new chart
`/chart update <id> "<new-text>" [category] [importance]` — Update existing
`/chart list [limit]` — List charts (default 20)
`/chart stale` — Scan for stale entries

**Categories:** reading, procedure, course, issue, error, agent, vision, model, architecture
**Importance:** 1.0=critical, 0.9=important, 0.8=standard, 0.5=nice-to-know

**Examples:**
`/chart search qmd`
`/chart read definition-chart`
`/chart add decision-foo "We chose X because Y" course 0.9`
`/chart stale`
HELP
}

case "$CMD" in
  search)  cmd_search "$1" ;;
  read)    cmd_read "$1" ;;
  add)     cmd_add "$1" "$2" "${3:-}" "${4:-}" ;;
  update)  cmd_update "$1" "$2" "${3:-}" "${4:-}" ;;
  list)    cmd_list "${1:-}" ;;
  stale)   cmd_stale ;;
  delete)
    echo "Delete requires the --confirm flag for safety."
    echo "Usage: /chart delete <id> --confirm"
    echo "Use the host CLI instead: chart delete <id>"
    ;;
  help|*)  cmd_help ;;
esac
