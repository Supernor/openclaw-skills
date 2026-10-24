#!/bin/sh
# === INTENT === T-OFF standby sentinel (Robert 2026-10-23 12:27 PM "use less tokens but not lose visibility"; 12:29 PM probe "the same surfaces of the MCP I'll be testing"; 12:32 PM "have it escalate ... increase from five minutes to an increased amount of time, as it becomes more reliable"). Runs where: host, background Bash inside the Claude Code tmux session.
# === HOW === interval starts 300 s; after every 6 clean rounds it doubles (cap 3600 s); any FAIL or LAG resets it to 300 s. Scheduled checks (dispatch, drill, r2) are slot-based, so a long sleep never skips one. EXITS (= wakes Reactor) only on a repeated fault or at window end.
# === LOG === rounds -> logs/t-off-sentinel.log (with the interval); per-tool timings -> logs/t-off-probe.log; wakes -> logs/t-off-wakes.log (counted against "solo" in post-flight).
END_EPOCH=$(date -d "2026-10-24 12:45:00 EDT" +%s)
DB=/root/.openclaw/ops.db; LOG=/root/.openclaw/logs/t-off-sentinel.log; WAKES=/root/.openclaw/logs/t-off-wakes.log; PROBE=/root/.openclaw/logs/t-off-probe.log
TOOLS="knownself_limits knownself_directory knownself_status_board knownself_read_messages knownself_presence knownself_get_document knownself_changes"
LAG_MS=1000; MIN_IVL=300; MAX_IVL=3600; CLEAN_FOR_STEP=6
q() { sqlite3 -readonly "$DB" "$1" 2>/dev/null; }
wake() { echo "$(date -u +%FT%TZ) WAKE: $1" | tee -a "$WAKES" >> "$LOG"; echo "T-OFF SENTINEL WAKE: $1"; exit 0; }
ivl=$MIN_IVL; clean=0; fails=""; last_slot=""; drill_day=""; r2_day=""
while :; do
  now=$(date +%s); ts=$(date -u +%FT%TZ); incident=""
  [ "$now" -ge "$END_EPOCH" ] && wake "window ended Sat 12:45 PM ET: run post-flight"
  for c in openclaw-openclaw-gateway-1 knownself-public; do
    st=$(docker inspect -f '{{.State.Status}} {{.State.Health.Status}}' "$c" 2>/dev/null)
    case "$st" in "running healthy") ;; *) incident="container:$c"; sleep 120; st2=$(docker inspect -f '{{.State.Status}} {{.State.Health.Status}}' "$c" 2>/dev/null); [ "$st2" = "running healthy" ] || wake "container $c = '$st2' for 2 min";; esac
  done
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST https://mcp.knownself.ai/mcp -H 'content-type: application/json' -d '{}' 2>/dev/null)
  case "$code" in 401|400|415|200) ;; *) incident="door:$code"; sleep 60; code2=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST https://mcp.knownself.ai/mcp -H 'content-type: application/json' -d '{}' 2>/dev/null); case "$code2" in 401|400|415|200) ;; *) wake "public MCP door answered '$code2' twice";; esac;; esac
  for u in openclaw-host-ops knownself-mcp-front knownself-credmint knownself-cred-pickup knownself-approval-poll knownself-documents-reader knownself-oauth; do
    systemctl is-active --quiet "$u" || wake "service $u not active"
  done
  newfails=""
  for t in $TOOLS; do
    s=$(date +%s%N); line=$(TD_KEY=/root/.openclaw/config/tool-drill-key.json python3 /root/.openclaw/scripts/tool-drill.py --observe --only "$t" 2>&1 | grep -E "^(PASS|FAIL|SKIP) " | head -1); wall=$(( ($(date +%s%N)-s)/1000000 ))
    status=$(echo "$line" | awk '{print $1}'); ms=$(echo "$line" | grep -oE '[0-9]+ms' | head -1 | tr -dc 0-9); [ -z "$status" ] && status=FAIL
    lag=""; if [ "${ms:-0}" -gt "$LAG_MS" ]; then lag=" LAG"; incident="lag:$t"; fi
    echo "$ts $t $status server=${ms:-NA}ms wall=${wall}ms$lag" >> "$PROBE"
    if [ "$status" = "FAIL" ]; then incident="fail:$t"; newfails="$newfails $t"; case " $fails " in *" $t "*) wake "feature $t FAILED twice in a row: $(echo "$line" | cut -c1-160)";; esac; fi
  done
  fails="$newfails"
  avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo); [ "$avail" -lt 400 ] && wake "memory avail ${avail} MB"; [ "$avail" -lt 900 ] && incident="mem:$avail"
  disk=$(df --output=pcent / | tail -1 | tr -dc 0-9); [ "$disk" -ge 93 ] && wake "disk ${disk}%"
  lp=/root/.openclaw/logs/liaison-poll.log; age=$(( now - $(stat -c %Y "$lp") )); [ "$age" -gt 1200 ] && wake "liaison-poll log silent ${age}s"
  tl=/root/.openclaw/logs/captain-mail-triage.log; age=$(( now - $(stat -c %Y "$tl") )); [ "$age" -gt 1500 ] && wake "captain-mail-triage log silent ${age}s"
  # slot-based: latest dispatch slot (18:23/00:23/06:23/12:23Z) that ended 25+ min ago must have a goal.dispatch at or after it
  slot=$(q "select max(s) from (select strftime('%Y-%m-%dT%H:%M:%SZ', datetime('now', '-25 minutes', 'start of day', '+' || h || ' hours', '+23 minutes')) s from (select 0 h union select 6 union select 12 union select 18)) where s <= strftime('%Y-%m-%dT%H:%M:%SZ','now','-25 minutes')")
  if [ -n "$slot" ] && [ "$slot" != "$last_slot" ]; then last=$(q "select max(ts) from ks_events where type='goal.dispatch'"); [ "$last" \< "$slot" ] && wake "goal.dispatch missing for slot $slot (last $last)"; last_slot="$slot"; fi
  today=$(date -u +%Y-%m-%d); hm=$(date -u +%H%M)
  if [ "$hm" -ge 0640 ] && [ "$drill_day" != "$today" ]; then grep -q "TOOL DRILL $today" /root/.openclaw/logs/tool-drill.log || wake "tool drill missing for $today"; drill_day=$today; fi
  if [ "$hm" -ge 0415 ] && [ "$r2_day" != "$today" ]; then grep -q "$today.*r2-backup OK" /root/.openclaw/logs/r2-backup.log 2>/dev/null || wake "r2 nightly not OK by 04:15Z"; r2_day=$today; fi
  dead=$(q "select count(*) from v_codex_pools where state not in ('healthy')"); [ "${dead:-0}" -ge 2 ] && wake "both codex pools not healthy"; [ "${dead:-0}" -ge 1 ] && incident="pool"
  if [ -n "$incident" ]; then ivl=$MIN_IVL; clean=0; else clean=$((clean+1)); if [ "$clean" -ge "$CLEAN_FOR_STEP" ]; then clean=0; ivl=$((ivl*2)); [ "$ivl" -gt "$MAX_IVL" ] && ivl=$MAX_IVL; fi; fi
  echo "$ts ok mem=${avail}MB disk=${disk}% door=$code incident=[${incident}] next=${ivl}s clean=$clean" >> "$LOG"
  sleep "$ivl"
done
