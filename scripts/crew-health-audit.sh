#!/usr/bin/env bash
# crew-health-audit.sh — Gather agent health data for satisfaction scoring
# Run from host. Outputs structured data for the crew-health skill.

set -eo pipefail

CONFIG="/root/.openclaw/openclaw.json"
LEDGER_DB="/root/.openclaw/bridge/reactor-ledger.sqlite"
COMPOSE_DIR="/root/openclaw"

echo "=== CREW HEALTH AUDIT — $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# 1. Agent inventory
echo ""
echo "--- AGENTS ---"
jq -r '.agents.list[] | "\(.id) | \(.name) | \(.model.primary)"' "$CONFIG"

# 2. Skill counts per workspace
echo ""
echo "--- SKILLS PER AGENT ---"
for ws in /root/.openclaw/workspace*/; do
  agent=$(basename "$ws")
  count=$(find "$ws/skills" -name "SKILL.md" 2>/dev/null | wc -l)
  skills=$(find "$ws/skills" -name "SKILL.md" 2>/dev/null | while read -r f; do basename "$(dirname "$f")"; done | paste -sd',' 2>/dev/null || echo "none")
  echo "$agent | $count skills | $skills"
done

# 3. Workspace file completeness
echo ""
echo "--- WORKSPACE FILES ---"
for ws in /root/.openclaw/workspace*/; do
  agent=$(basename "$ws")
  files=""
  for f in SOUL.md AGENTS.md CLAUDE.md IDENTITY.md MEMORY.md TOOLS.md USER.md HEARTBEAT.md; do
    if [ -e "$ws/$f" ]; then
      files="${files}+${f} "
    else
      files="${files}-${f} "
    fi
  done
  echo "$agent | $files"
done

# 4. SOUL.md sizes
echo ""
echo "--- SOUL.MD SIZES ---"
for ws in /root/.openclaw/workspace*/; do
  agent=$(basename "$ws")
  if [ -f "$ws/SOUL.md" ]; then
    lines=$(wc -l < "$ws/SOUL.md")
    chars=$(wc -c < "$ws/SOUL.md")
    echo "$agent | ${lines} lines | ${chars} chars"
  else
    echo "$agent | MISSING"
  fi
done

# 5. Reactor ledger stats (if available)
echo ""
echo "--- REACTOR LEDGER ---"
if [ -f "$LEDGER_DB" ]; then
  echo "Total tasks: $(sqlite3 "$LEDGER_DB" "SELECT COUNT(*) FROM jobs;" 2>/dev/null)"
  echo "By status:"
  sqlite3 "$LEDGER_DB" "SELECT status, COUNT(*) as cnt FROM jobs GROUP BY status ORDER BY cnt DESC;" 2>/dev/null
  echo "By requester:"
  sqlite3 "$LEDGER_DB" "SELECT requested_by, COUNT(*) as cnt FROM jobs GROUP BY requested_by ORDER BY cnt DESC;" 2>/dev/null
  echo "Avg duration (completed): $(sqlite3 "$LEDGER_DB" "SELECT COALESCE(CAST(AVG(duration_seconds) AS INTEGER), 0) FROM jobs WHERE status='completed';" 2>/dev/null)s"
else
  echo "(no ledger found)"
fi

# 6. Model health
echo ""
echo "--- MODEL HEALTH ---"
cd "$COMPOSE_DIR"
docker compose logs --tail=5 openclaw-gateway 2>&1 | grep "Health check" | tail -1 | sed 's/.*Health check complete: //'

# 7. Container tool availability
echo ""
echo "--- TOOL AVAILABILITY ---"
docker compose exec openclaw-gateway bash -c '
  echo "chromium: $(which chromium 2>/dev/null && echo YES || echo NO)"
  echo "gemini-cli: $(which gemini 2>/dev/null && echo YES || echo NO)"
  echo "node: $(which node 2>/dev/null && echo YES || echo NO)"
  echo "jq: $(which jq 2>/dev/null && echo YES || echo NO)"
  echo "sqlite3: $(which sqlite3 2>/dev/null && echo YES || echo NO)"
  echo "curl: $(which curl 2>/dev/null && echo YES || echo NO)"
  echo "git: $(which git 2>/dev/null && echo YES || echo NO)"
  echo "gemini-api: $(curl -s -o /dev/null -w "%{http_code}" "https://generativelanguage.googleapis.com/v1beta/models?key=${OPENCLAW_PROD_GOOGLE_AI_KEY}" 2>/dev/null)"
' 2>&1 | grep -v "level=warning"

# 8. Chartroom stats
echo ""
echo "--- CHARTROOM ---"
docker compose exec openclaw-gateway node -e "
  import('/app/extensions/memory-lancedb/node_modules/@lancedb/lancedb/dist/index.js').then(async (m) => {
    const db = await m.default.connect('/home/node/.openclaw/memory/lancedb');
    const t = await db.openTable('memories');
    const all = await t.query().limit(500).toArray();
    const cats = {};
    for (const r of all) { const c = r.category || 'unset'; cats[c] = (cats[c]||0)+1; }
    console.log('Total entries:', all.length);
    for (const [k,v] of Object.entries(cats).sort((a,b)=>b[1]-a[1])) console.log('  '+k+': '+v);
  });
" 2>&1 | grep -v "level=warning"

echo ""
echo "=== AUDIT COMPLETE ==="
