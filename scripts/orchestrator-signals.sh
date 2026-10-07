#!/bin/bash
# === INTENT ===
# Zero-model orchestrator signal digest: one normalized text block of everything the
# Reactor orchestrator wants to be woken for. Watched by a session-side loop that
# diffs consecutive runs and exits (= notifies the orchestrator) only on change.
DB=/root/.openclaw/ops.db
echo "== deferred open =="
sqlite3 "$DB" "SELECT id||'|'||owner||'|'||substr(title,1,60) FROM deferred_items WHERE status='open' ORDER BY id;" 2>/dev/null
echo "== tasks active/blocked =="
sqlite3 "$DB" "SELECT id||'|'||status||'|'||attempt_count||'|'||substr(task,1,50) FROM tasks WHERE status IN ('in_progress','blocked') ORDER BY id;" 2>/dev/null
echo "== evidence/sham flags (1h) =="
sqlite3 "$DB" "SELECT id FROM tasks WHERE outcome LIKE '%EVIDENCE-FAIL%' AND updated_at > datetime('now','-1 hour');" 2>/dev/null
echo "== pools =="
sqlite3 "$DB" "SELECT key||'='||json_extract(value,'$.status') FROM kv WHERE key IN ('codex_pool_a_probe','codex_pool_b_probe');" 2>/dev/null
sqlite3 "$DB" "SELECT key FROM kv WHERE key IN ('codex_task_cooldown','codex_pool_b_needs_reauth','codex_pool_a_exhausted');" 2>/dev/null
echo "== seat =="
python3 -c "import json;d=json.load(open('/tmp/claude-seat.json'));print('five_pct_band='+str(d['five_pct']//10*10),'week_pct_band='+str(d['week_pct']//10*10),'fleet='+str(d['fleet']),'health_worst='+str(d['health_worst']))" 2>/dev/null
echo "== services =="
for s in openclaw-host-ops openclaw-bridge-dev; do printf '%s=%s\n' "$s" "$(systemctl is-active $s 2>/dev/null)"; done
echo "== backbone =="
sqlite3 /root/.openclaw/ops.db "SELECT 'messages='||COUNT(*) FROM bb_messages; SELECT 'proposals='||COUNT(*) FROM bb_proposals; SELECT 'decisions='||COUNT(*) FROM bb_proposal_decisions;" 2>/dev/null
python3 -c "import json;d=json.load(open('/srv/knownself-public/runtime/backbone-switch.json'));print('switch='+str(d.get('enabled')))" 2>/dev/null
