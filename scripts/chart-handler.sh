#!/usr/bin/env bash
# chart-handler.sh - Container-side /chart command handler.
# Runs INSIDE the OpenClaw gateway container. The host CLI at /usr/local/bin/chart
# uses docker compose exec; this handler starts from the already-containerized side.
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
LDB_MOD="/home/node/.openclaw/extensions/memory-lancedb/node_modules/@lancedb/lancedb/dist/index.js"
OPENAI_MOD="/home/node/.openclaw/extensions/memory-lancedb/node_modules/openai/index.mjs"
QUEUE_FILE="/home/node/.openclaw/chart-queue.jsonl"
OLLAMA_EMBED_URL="${OLLAMA_EMBED_URL:-http://172.17.0.1:11434/api/embed}"
VALID_CATEGORIES="agent architecture changelog course decision entity error fact governance issue model other policy preference procedure project reading skill vision"

# Fallback paths for host execution
if [ ! -d "/app/extensions" ] && [ -d "/root/.openclaw" ]; then
  echo '{"error":"This script runs inside the container. Use /usr/local/bin/chart on the host."}'
  exit 1
fi

_require_lancedb() {
  if [ ! -f "$LDB_MOD" ]; then
    echo "ERROR: Chart system cannot find lancedb module." >&2
    echo "  WHAT: $LDB_MOD is missing inside the container." >&2
    echo "  FIX: Restore /home/node/.openclaw/extensions/memory-lancedb/node_modules/." >&2
    echo "  VERIFY: ls /home/node/.openclaw/extensions/memory-lancedb/node_modules/@lancedb/" >&2
    exit 1
  fi
  if [ ! -d "$LDB_PATH" ]; then
    echo "ERROR: Chart LanceDB path is missing: $LDB_PATH" >&2
    exit 1
  fi
}

_run_node() {
  LDB_PATH="$LDB_PATH" \
  LDB_MOD="$LDB_MOD" \
  OPENAI_MOD="$OPENAI_MOD" \
  OLLAMA_EMBED_URL="$OLLAMA_EMBED_URL" \
  node --input-type=module
}

_sanitize_id() {
  echo "$1" | tr -cd 'a-zA-Z0-9-'
}

_validate_id_format() {
  local id="$1"
  if ! echo "$id" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
    echo "WARNING: ID '$id' does not match recommended format (lowercase alphanumeric + hyphens)"
  fi
}

_validate_category() {
  local category="$1"
  local cat
  for cat in $VALID_CATEGORIES; do
    if [ "$category" = "$cat" ]; then
      return 0
    fi
  done
  echo "ERROR: Invalid category '$category'"
  echo "Valid categories: $VALID_CATEGORIES"
  exit 1
}

_validate_importance() {
  local importance="$1"
  if echo "$importance" | grep -qE '^0(\.[0-9]+)?$|^1(\.0+)?$'; then
    return 0
  fi
  echo "ERROR: Importance must be between 0.0 and 1.0 (got '$importance')"
  exit 1
}

_chart_exists() {
  local safe_id="$1"
  CHART_SAFE_ID="$safe_id" _run_node <<'SCRIPT'
try {
  const { pathToFileURL } = await import('node:url');
  const lancedb = (await import(pathToFileURL(process.env.LDB_MOD).href)).default;
  const db = await lancedb.connect(process.env.LDB_PATH);
  const table = await db.openTable('memories');
  const rows = await table.query().where(`id = '${process.env.CHART_SAFE_ID}'`).limit(1).toArray();
  console.log(rows.length > 0 ? 'EXISTS' : 'NEW');
} catch (err) {
  console.error('ERROR: ' + (err?.message || err));
  process.exit(1);
}
SCRIPT
}

_existing_meta() {
  local safe_id="$1"
  CHART_SAFE_ID="$safe_id" _run_node <<'SCRIPT'
try {
  const { pathToFileURL } = await import('node:url');
  const lancedb = (await import(pathToFileURL(process.env.LDB_MOD).href)).default;
  const db = await lancedb.connect(process.env.LDB_PATH);
  const table = await db.openTable('memories');
  const rows = await table.query().where(`id = '${process.env.CHART_SAFE_ID}'`).limit(1).toArray();
  if (rows.length > 0) {
    console.log(JSON.stringify({
      category: rows[0].category || 'reading',
      importance: rows[0].importance || 0.8
    }));
  } else {
    console.log(JSON.stringify({ category: 'reading', importance: 0.8 }));
  }
} catch (err) {
  console.error('ERROR: ' + (err?.message || err));
  process.exit(1);
}
SCRIPT
}

_queue_entry() {
  local action="$1" id="$2" text="$3" category="$4" importance="$5" reason="${6:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$(dirname "$QUEUE_FILE")"
  jq -nc \
    --arg id "$id" \
    --arg text "$text" \
    --arg category "$category" \
    --arg importance "$importance" \
    --arg queued_at "$ts" \
    --arg action "$action" \
    --arg reason "$reason" \
    '{id:$id,text:$text,category:$category,importance:($importance|tonumber),queued_at:$queued_at,status:"pending",action:$action,reason:$reason}' \
    >> "$QUEUE_FILE"
  echo "Queued: $id ($category)"
  echo "Direct $action failed; queued in $QUEUE_FILE"
  if [ -n "$reason" ]; then
    printf 'Reason: %s\n' "$(printf '%s' "$reason" | tr '\n' ' ' | cut -c1-240)"
  fi
}

_write_direct() {
  local action="$1" id="$2" safe_id="$3" text="$4" category="$5" importance="$6"
  CHART_ACTION="$action" \
  CHART_ID="$id" \
  CHART_SAFE_ID="$safe_id" \
  CHART_TEXT="$text" \
  CHART_CATEGORY="$category" \
  CHART_IMPORTANCE="$importance" \
  CHART_FORCE="${CHART_FORCE:-}" \
  _run_node <<'SCRIPT'
try {
  const { pathToFileURL } = await import('node:url');
  const lancedb = (await import(pathToFileURL(process.env.LDB_MOD).href)).default;
  const db = await lancedb.connect(process.env.LDB_PATH);
  const table = await db.openTable('memories');

  const action = process.env.CHART_ACTION;
  const id = process.env.CHART_ID;
  const safeId = process.env.CHART_SAFE_ID;
  const text = process.env.CHART_TEXT;
  const category = process.env.CHART_CATEGORY || 'reading';
  const importance = Number(process.env.CHART_IMPORTANCE || '0.8') || 0.8;
  const force = process.env.CHART_FORCE === '1';

  const existing = await table.query().where(`id = '${safeId}'`).limit(1).toArray();
  if (action === 'add' && existing.length > 0 && !force) {
    console.error(`WARNING: Chart '${id}' already exists. Use CHART_FORCE=1 to overwrite.`);
    process.exit(1);
  }

  const resp = await fetch(process.env.OLLAMA_EMBED_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'nomic-embed-text', input: text })
  });
  if (!resp.ok) {
    const body = await resp.text();
    console.error(`Embedding request failed: ${resp.status} ${resp.statusText}: ${body.slice(0, 200)}`);
    process.exit(1);
  }
  const data = await resp.json();
  const vector = data.embeddings?.[0] || data.embedding;
  if (!Array.isArray(vector)) {
    console.error('Embedding response did not include a vector.');
    process.exit(1);
  }

  const sample = await table.query().limit(1).toArray();
  const fields = Object.keys(sample[0] || {
    id: null,
    text: null,
    vector: null,
    importance: null,
    category: null,
    createdAt: null,
    updatedAt: null
  });
  const expected = sample[0]?.vector?.length || 768;
  if (vector.length !== expected) {
    console.error(`Dimension mismatch: got ${vector.length}, expected ${expected}`);
    process.exit(1);
  }

  const entry = {};
  for (const field of fields) entry[field] = null;
  entry.id = id;
  entry.text = text;
  entry.vector = vector;
  entry.importance = importance;
  entry.category = category;
  entry.createdAt = Date.now();
  entry.updatedAt = Date.now();

  if (action === 'update' || force) {
    await table.delete(`id = '${safeId}'`);
  }
  await table.add([entry]);
  console.log('Charted: ' + entry.id + ' [' + entry.category + '] importance=' + entry.importance);
} catch (err) {
  console.error('ERROR: ' + (err?.message || err));
  process.exit(1);
}
SCRIPT
}

_import_registry() {
  local id="$1" text="$2" category="$3" importance="$4" _reg_rc
  if python3 /home/node/.openclaw/scripts/mem-import-charts.py --one "$id" \
    --text "$text" --category "$category" --importance "$importance"; then
    _reg_rc=0
  else
    _reg_rc=$?
  fi
  if [ "$_reg_rc" -eq 2 ]; then
    echo "WARN chart->registry write FAILED for '$id' (mem-import-charts exit 2)." >&2
    echo "  The chart IS in LanceDB (vector tier) but NOT in the KnownSelf registry." >&2
    printf "  Fix: python3 /home/node/.openclaw/scripts/mem-import-charts.py --one %q --text %q --category %q --importance %q\n" "$id" "$text" "$category" "$importance" >&2
    echo "  The daily reconciler will also flag this id as new_unshimmed until repaired." >&2
  fi
}

cmd_search() {
  local keywords="$*"
  if [ -z "$keywords" ]; then
    echo "Usage: /chart search <keywords>"
    exit 1
  fi
  _require_lancedb
  CHART_KEYWORDS="$keywords" _run_node <<'SCRIPT'
try {
  const { pathToFileURL } = await import('node:url');
  const lancedb = (await import(pathToFileURL(process.env.LDB_MOD).href)).default;
  const db = await lancedb.connect(process.env.LDB_PATH);
  const table = await db.openTable('memories');
  const resp = await fetch(process.env.OLLAMA_EMBED_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'nomic-embed-text', input: process.env.CHART_KEYWORDS })
  });
  if (!resp.ok) {
    const body = await resp.text();
    console.error(`Embedding request failed: ${resp.status} ${resp.statusText}: ${body.slice(0, 200)}`);
    process.exit(1);
  }
  const data = await resp.json();
  const vector = data.embeddings?.[0] || data.embedding;
  if (!Array.isArray(vector)) {
    console.error('Embedding response did not include a vector.');
    process.exit(1);
  }
  const results = await table.vectorSearch(vector).limit(10).toArray();
  if (results.length === 0) {
    console.log('No results found.');
    process.exit(0);
  }
  for (const row of results) {
    const score = Math.round((1 / (1 + (row._distance || 0))) * 100) / 100;
    const cat = String(row.category || 'unset').padEnd(14);
    const preview = String(row.text || '').substring(0, 120).replace(/\n/g, ' ');
    const ts = row.updatedAt || row.createdAt;
    const asOf = ts ? new Date(Number(ts)).toISOString().slice(0, 10) : 'undated';
    const stale = /^SUPERSEDED/i.test(String(row.text || '')) ? '  [SUPERSEDED — follow pointer]' : '';
    console.log(`${score}  ${asOf}  ${cat}${row.id}${stale}`);
    console.log(`    ${preview}...`);
    console.log('');
  }
} catch (err) {
  console.error('ERROR: ' + (err?.message || err));
  process.exit(1);
}
SCRIPT
}

cmd_read() {
  local id="$1"
  if [ -z "$id" ]; then
    echo "Usage: /chart read <id>"
    exit 1
  fi
  _require_lancedb
  local safe_id
  safe_id=$(_sanitize_id "$id")
  if [ -z "$safe_id" ]; then
    echo "Not found: $id"
    exit 1
  fi
  CHART_ID="$id" CHART_SAFE_ID="$safe_id" _run_node <<'SCRIPT'
try {
  const { pathToFileURL } = await import('node:url');
  const lancedb = (await import(pathToFileURL(process.env.LDB_MOD).href)).default;
  const db = await lancedb.connect(process.env.LDB_PATH);
  const table = await db.openTable('memories');
  const rows = await table.query().where(`id = '${process.env.CHART_SAFE_ID}'`).limit(1).toArray();
  if (rows.length === 0) {
    console.log('Not found: ' + process.env.CHART_ID);
    process.exit(1);
  }
  const r = rows[0];
  console.log('**' + r.id + '** [' + (r.category || 'unset') + '] importance: ' + (r.importance || 0));
  console.log('');
  console.log(r.text || '(empty)');
} catch (err) {
  console.error('ERROR: ' + (err?.message || err));
  process.exit(1);
}
SCRIPT
}

cmd_add() {
  local id="$1" text="$2" category="${3:-reading}" importance="${4:-0.8}"
  if [ -z "$id" ] || [ -z "$text" ]; then
    echo "Usage: /chart add <id> \"<text>\" [category] [importance]"
    exit 1
  fi
  _require_lancedb
  _validate_id_format "$id"
  _validate_category "$category"
  _validate_importance "$importance"

  local safe_id exists output
  safe_id=$(_sanitize_id "$id")
  if [ -z "$safe_id" ]; then
    echo "ERROR: Invalid chart id '$id'"
    exit 1
  fi
  exists=$(_chart_exists "$safe_id" 2>/dev/null || echo "UNKNOWN")
  if [ "$exists" = "EXISTS" ] && [ "${CHART_FORCE:-}" != "1" ]; then
    echo "WARNING: Chart '$id' already exists. Use CHART_FORCE=1 to overwrite."
    exit 1
  fi

  if output=$(_write_direct add "$id" "$safe_id" "$text" "$category" "$importance" 2>&1); then
    printf '%s\n' "$output"
    _import_registry "$id" "$text" "$category" "$importance"
  else
    if echo "$output" | grep -q "already exists"; then
      printf '%s\n' "$output"
      exit 1
    fi
    _queue_entry add "$id" "$text" "$category" "$importance" "$output"
  fi
}

cmd_update() {
  local id="$1" text="$2" category="${3:-}" importance="${4:-}"
  if [ -z "$id" ] || [ -z "$text" ]; then
    echo "Usage: /chart update <id> \"<new-text>\" [category] [importance]"
    exit 1
  fi
  _require_lancedb

  local today safe_id existing output
  today=$(date -u +%Y-%m-%d)
  if ! echo "$text" | grep -q "Verified:"; then
    text="${text} Verified: ${today}."
  fi
  safe_id=$(_sanitize_id "$id")
  if [ -z "$safe_id" ]; then
    echo "ERROR: Invalid chart id '$id'"
    exit 1
  fi

  if [ -z "$category" ] || [ -z "$importance" ]; then
    existing=$(_existing_meta "$safe_id" 2>/dev/null || echo '{"category":"reading","importance":0.8}')
    [ -z "$category" ] && category=$(echo "$existing" | jq -r '.category // "reading"' 2>/dev/null || echo "reading")
    [ -z "$importance" ] && importance=$(echo "$existing" | jq -r '.importance // 0.8' 2>/dev/null || echo "0.8")
  fi
  _validate_category "$category"
  _validate_importance "$importance"

  if output=$(_write_direct update "$id" "$safe_id" "$text" "$category" "$importance" 2>&1); then
    printf '%s\n' "$output"
    echo "(updated with Verified: ${today})"
    _import_registry "$id" "$text" "$category" "$importance"
  else
    _queue_entry update "$id" "$text" "$category" "$importance" "$output"
  fi
}

cmd_list() {
  local limit="${1:-20}"
  _require_lancedb
  CHART_LIMIT="$limit" _run_node <<'SCRIPT'
try {
  const { pathToFileURL } = await import('node:url');
  const lancedb = (await import(pathToFileURL(process.env.LDB_MOD).href)).default;
  const db = await lancedb.connect(process.env.LDB_PATH);
  const table = await db.openTable('memories');
  const parsedLimit = Number.parseInt(process.env.CHART_LIMIT || '20', 10);
  const limit = Number.isFinite(parsedLimit) && parsedLimit > 0 ? parsedLimit : 20;
  const all = await table.query().limit(limit).toArray();
  for (const r of all) {
    const cat = String(r.category || 'unset').padEnd(12);
    const imp = Number(r.importance || 0).toFixed(1);
    const preview = String(r.text || '').substring(0, 80).replace(/\n/g, ' ');
    console.log(cat + ' ' + imp + '  ' + r.id + '  ' + preview + '...');
  }
  console.log('');
  console.log('Total: ' + all.length + ' entries (showing up to ' + limit + ')');
} catch (err) {
  console.error('ERROR: ' + (err?.message || err));
  process.exit(1);
}
SCRIPT
}

cmd_stale() {
  local today_epoch
  today_epoch=$(date -u +%s)
  _require_lancedb

  echo "Scanning Chartroom for stale entries..."

  local entries
  entries=$(CHART_LIMIT="500" _run_node <<'SCRIPT'
try {
  const { pathToFileURL } = await import('node:url');
  const lancedb = (await import(pathToFileURL(process.env.LDB_MOD).href)).default;
  const db = await lancedb.connect(process.env.LDB_PATH);
  const table = await db.openTable('memories');
  const all = await table.query().limit(500).toArray();
  for (const r of all) {
    const cat = r.category || 'reading';
    const text = String(r.text || '').replace(/\n/g, ' ');
    console.log(JSON.stringify({ id: r.id, category: cat, text }));
  }
} catch (err) {
  console.error('ERROR: ' + (err?.message || err));
  process.exit(1);
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
**/chart** - Chartroom commands

`/chart search <keywords>` - Semantic search
`/chart read <id>` - Read a specific chart
`/chart add <id> "<text>" [category] [importance]` - Add new chart
`/chart update <id> "<new-text>" [category] [importance]` - Update existing
`/chart list [limit]` - List charts (default 20)
`/chart stale` - Scan for stale entries

**Categories:** agent, architecture, changelog, course, decision, entity, error, fact, governance, issue, model, other, policy, preference, procedure, project, reading, skill, vision
**Importance:** 1.0=critical, 0.9=important, 0.8=standard, 0.5=nice-to-know

**Examples:**
`/chart search qmd`
`/chart read definition-chart`
`/chart add decision-foo "We chose X because Y" course 0.9`
`/chart stale`
HELP
}

CMD="${1:-help}"
if [ $# -gt 0 ]; then
  shift
fi

case "$CMD" in
  search)  cmd_search "$@" ;;
  read)    cmd_read "${1:-}" ;;
  add)     cmd_add "${1:-}" "${2:-}" "${3:-reading}" "${4:-0.8}" ;;
  update)  cmd_update "${1:-}" "${2:-}" "${3:-}" "${4:-}" ;;
  list)    cmd_list "${1:-}" ;;
  stale)   cmd_stale ;;
  delete)
    echo "Delete requires the --confirm flag for safety."
    echo "Usage: /chart delete <id> --confirm"
    echo "Use the host CLI instead: chart delete <id>"
    ;;
  help|*)  cmd_help ;;
esac
