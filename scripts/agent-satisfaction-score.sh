#!/usr/bin/env bash
# agent-satisfaction-score.sh — Score 19 intents per agent
#
# Aligned to the intent-based governance framework (2026-03-07).
# Every intent scored per-agent, 0-10, from measurable signals only.
# System-wide signals (like shared memory) propagate to all agents.
#
# System is driven by two dimensions:
#   Intent [I##] — quality of execution (HOW well)
#   Purpose Toward Vision [P##] — alignment to goals (WHY)
# Plus two derived reports (no extra tags):
#   Progress — completed work per P-code
#   Method — which engine/agent (from ledger)
#
# Intent Groups (19 intents):
#   EXECUTION:  Accurate, Competent, Reliable, Efficient, Resourceful
#   RESILIENCE: Resilient, Trusted, Recoverable
#   GROWTH:     Growing, Adaptive, Autonomous, Informed
#   CONNECTION: Understood, Responsive, Connected
#   AWARENESS:  Aware, Observable, Coherent, Secure
#
# Usage:
#   agent-satisfaction-score.sh              # human-readable report
#   agent-satisfaction-score.sh --json       # machine-readable
#   agent-satisfaction-score.sh --agent relay # single agent detail

set -o pipefail

MODE="${1:-report}"
FILTER_AGENT="${2:-}"
COMPOSE_DIR="/root/openclaw"
LEDGER="/root/.openclaw/bridge/reactor-ledger.sqlite"
LOG_DIR="/root/.openclaw/logs"
HEALTH_BUFFER="/root/.openclaw/health/buffer.jsonl"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

AGENTS=("relay" "main" "spec-projects" "spec-github" "spec-dev" "spec-reactor" "spec-browser" "spec-research" "spec-security" "spec-ops" "spec-design" "spec-systems" "spec-comms")
AGENT_NAMES=("Relay" "Captain" "Scribe" "Repo-Man" "Dev" "Reactor Mgr" "Navigator" "Research" "Security" "Ops Officer" "Designer" "Sys Engineer" "Comms Officer")

INTENT_IDS=(I01 I02 I03 I04 I05 I06 I07 I08 I09 I10 I11 I12 I13 I14 I15 I16 I17 I18 I19)
INTENT_NAMES=(Accurate Understood Competent Responsive Reliable Efficient Resourceful Resilient Growing Connected Trusted Aware Observable Adaptive Recoverable Secure Autonomous Informed Coherent)

# ─── HELPERS ───
pct_to_inverse_score() {
  local pct=$1
  if [ "$pct" -le 0 ]; then echo 10
  elif [ "$pct" -le 25 ]; then echo 10
  elif [ "$pct" -le 50 ]; then echo 8
  elif [ "$pct" -le 70 ]; then echo 6
  elif [ "$pct" -le 85 ]; then echo 4
  elif [ "$pct" -le 100 ]; then echo 2
  else echo 0
  fi
}

pct_to_score() {
  local pct=$1
  if [ "$pct" -ge 100 ]; then echo 10
  elif [ "$pct" -ge 90 ]; then echo 9
  elif [ "$pct" -ge 75 ]; then echo 8
  elif [ "$pct" -ge 60 ]; then echo 7
  elif [ "$pct" -ge 40 ]; then echo 5
  elif [ "$pct" -ge 20 ]; then echo 3
  else echo 1
  fi
}

clamp() {
  local v=$1
  [ "$v" -gt 10 ] && v=10
  [ "$v" -lt 0 ] && v=0
  echo "$v"
}

agent_ws() {
  local agent=$1
  if [ "$agent" = "main" ]; then
    echo "/root/.openclaw/workspace"
  else
    echo "/root/.openclaw/workspace-$agent"
  fi
}

# ═══════════════════════════════════════════════════════════════
# COLLECT DATA (one pass, shared across all intents)
# ═══════════════════════════════════════════════════════════════

declare -A CTX_PCT SESSION_COUNT SKILL_COUNT SOUL_LINES SOUL_BOUNDARIES
declare -A HAS_HEARTBEAT HAS_FALLBACK MODEL_ERRORS INTENT_TAG_COUNT
declare -A HAS_TOOLS_MD HAS_MEMORY_MD HAS_IDENTITY_MD

# --- Sessions + context ---
for i in "${!AGENTS[@]}"; do
  agent="${AGENTS[$i]}"
  json=$(cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway openclaw sessions --agent "$agent" --json 2>/dev/null | grep -v "level=warning") || true
  if [ -n "$json" ]; then
    peak=$(echo "$json" | jq '[.sessions // [] | .[] | select(.contextTokens > 0 and .totalTokens != null and .totalTokens > 0) | (.totalTokens / .contextTokens * 100 | floor)] | max // 0' 2>/dev/null) || true
    CTX_PCT[$agent]="${peak:-0}"
    count=$(echo "$json" | jq '.sessions | length' 2>/dev/null) || true
    SESSION_COUNT[$agent]="${count:-0}"
  else
    CTX_PCT[$agent]=0
    SESSION_COUNT[$agent]=0
  fi
done

# --- Skills + workspace files ---
for agent in "${AGENTS[@]}"; do
  ws=$(agent_ws "$agent")
  SKILL_COUNT[$agent]=$(ls -d "$ws/skills/"*/ 2>/dev/null | wc -l)

  if [ -f "$ws/SOUL.md" ]; then
    SOUL_LINES[$agent]=$(wc -l < "$ws/SOUL.md")
    SOUL_BOUNDARIES[$agent]=$(grep -ciE "(you do not|not your|never |don.t |outside your)" "$ws/SOUL.md" 2>/dev/null || echo 0)
  else
    SOUL_LINES[$agent]=0
    SOUL_BOUNDARIES[$agent]=0
  fi

  [ -f "$ws/TOOLS.md" ] && HAS_TOOLS_MD[$agent]="true" || HAS_TOOLS_MD[$agent]="false"
  [ -f "$ws/MEMORY.md" ] && HAS_MEMORY_MD[$agent]="true" || HAS_MEMORY_MD[$agent]="false"
  [ -f "$ws/IDENTITY.md" ] && HAS_IDENTITY_MD[$agent]="true" || HAS_IDENTITY_MD[$agent]="false"

  # Intent tags in skills
  tags=$(grep -rhoP 'I(?:0[1-9]|1[0-8])' "$ws/skills/" 2>/dev/null | sort -u | wc -l)
  INTENT_TAG_COUNT[$agent]="$tags"
done

# --- Heartbeat ---
for agent in "${AGENTS[@]}"; do
  [ "$agent" = "relay" ] && HAS_HEARTBEAT[$agent]="true" || HAS_HEARTBEAT[$agent]="false"
done

# --- Model fallback + errors ---
for agent in "${AGENTS[@]}"; do
  profiles_json=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway cat "/home/node/.openclaw/agents/$agent/agent/auth-profiles.json" 2>/dev/null | grep -v "level=warning") || true
  if [ -n "$profiles_json" ]; then
    pcount=$(echo "$profiles_json" | jq 'length // 0' 2>/dev/null) || true
    HAS_FALLBACK[$agent]=$([ "${pcount:-0}" -gt 1 ] && echo "true" || echo "false")
    errs=$(echo "$profiles_json" | jq '[to_entries[] | .value.errorCount // 0] | add // 0' 2>/dev/null) || true
    MODEL_ERRORS[$agent]="${errs:-0}"
  else
    HAS_FALLBACK[$agent]="false"
    MODEL_ERRORS[$agent]=0
  fi
done

# --- Reactor ledger ---
LEDGER_TOTAL=0; LEDGER_COMPLETED=0; LEDGER_FAILED=0
LEDGER_HANDOFFS_SENT=0; LEDGER_HANDOFFS_ACKED=0
if [ -f "$LEDGER" ]; then
  ledger_raw=$(sqlite3 "$LEDGER" "SELECT COUNT(*) || '|' || COALESCE(SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END),0) || '|' || COALESCE(SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END),0) || '|' || COALESCE(SUM(CASE WHEN relay_handoff_sent=1 THEN 1 ELSE 0 END),0) || '|' || COALESCE(SUM(CASE WHEN relay_handoff_acked=1 THEN 1 ELSE 0 END),0) FROM jobs" 2>/dev/null) || true
  IFS='|' read LEDGER_TOTAL LEDGER_COMPLETED LEDGER_FAILED LEDGER_HANDOFFS_SENT LEDGER_HANDOFFS_ACKED <<< "$ledger_raw"
fi

# --- Chartroom stats (shared, for I18 INFORMED) ---
chart_listing=$(chart list 300 2>/dev/null) || true
total_charts=$(echo "$chart_listing" | tail -1 | grep -oP '\d+' || echo "0")
error_charts=$(echo "$chart_listing" | grep -c "^issue\|^error" || echo "0")
vision_charts=$(echo "$chart_listing" | grep -c "^vision" || echo "0")

# --- Staleness count (for I18 INFORMED) — read from health buffer, not live scan ---
stale_chart_count=999
if [ -f "$HEALTH_BUFFER" ]; then
  latest_stale=$(grep '"chart-stale"' "$HEALTH_BUFFER" 2>/dev/null | tail -1) || true
  if [ -n "$latest_stale" ]; then
    stale_chart_count=$(echo "$latest_stale" | jq -r '.stale_count // 999' 2>/dev/null) || true
  fi
fi

# --- Health buffer freshness (for I13 OBSERVABLE) ---
buffer_age_hrs=999
if [ -f "$HEALTH_BUFFER" ]; then
  last_ts=$(tail -1 "$HEALTH_BUFFER" 2>/dev/null | jq -r '.ts // empty' 2>/dev/null) || true
  if [ -n "$last_ts" ]; then
    last_epoch=$(date -d "$last_ts" +%s 2>/dev/null) || true
    now_epoch=$(date +%s)
    if [ -n "$last_epoch" ]; then
      buffer_age_hrs=$(( (now_epoch - last_epoch) / 3600 ))
    fi
  fi
fi

# --- Security: config permissions (for I16 SECURE) ---
config_perms=$(stat -c %a /root/.openclaw/openclaw.json 2>/dev/null || echo "unknown")
env_perms=$(stat -c %a /root/openclaw/.env 2>/dev/null || echo "unknown")

# ═══════════════════════════════════════════════════════════════
# SCORE ALL 19 INTENTS PER AGENT
# ═══════════════════════════════════════════════════════════════

declare -A SCORES REASONS

for agent in "${AGENTS[@]}"; do

  # ─── I01 ACCURATE: Task completion rate, model error rate ───
  s=5; r=""
  if [ "$LEDGER_TOTAL" -gt 0 ]; then
    comp_pct=$((LEDGER_COMPLETED * 100 / LEDGER_TOTAL))
    s=$(pct_to_score $comp_pct)
    r="tasks ${LEDGER_COMPLETED}/${LEDGER_TOTAL} (${comp_pct}%)"
  else
    r="no task data"
  fi
  errs=${MODEL_ERRORS[$agent]:-0}
  [ "$errs" -gt 3 ] && s=$((s - 2)) && r="${r}, ${errs} model errors"
  SCORES["${agent}_I01"]=$(clamp $s)
  REASONS["${agent}_I01"]="$r"

  # ─── I02 UNDERSTOOD: SOUL.md quality + boundary statements ───
  soul=${SOUL_LINES[$agent]:-0}
  nots=${SOUL_BOUNDARIES[$agent]:-0}
  s=5
  [ "$soul" -gt 50 ] && s=$((s + 2))
  [ "$soul" -gt 100 ] && s=$((s + 1))
  [ "$nots" -gt 0 ] && s=$((s + 2))
  [ "$soul" -eq 0 ] && s=0
  SCORES["${agent}_I02"]=$(clamp $s)
  REASONS["${agent}_I02"]="SOUL.md: ${soul}L, ${nots} boundaries"

  # ─── I03 COMPETENT: Skills count in sweet spot + workspace files ───
  skills=${SKILL_COUNT[$agent]:-0}
  s=5
  [ "$skills" -ge 3 ] && [ "$skills" -le 7 ] && s=10
  [ "$skills" -ge 1 ] && [ "$skills" -lt 3 ] && s=7
  [ "$skills" -gt 7 ] && [ "$skills" -le 12 ] && s=8
  [ "$skills" -gt 12 ] && s=6
  [ "$skills" -eq 0 ] && s=3
  [ "${HAS_TOOLS_MD[$agent]}" = "true" ] && s=$((s + 0)) || s=$((s - 1))
  SCORES["${agent}_I03"]=$(clamp $s)
  REASONS["${agent}_I03"]="${skills} skills, TOOLS.md:${HAS_TOOLS_MD[$agent]}"

  # ─── I04 RESPONSIVE: Sessions active + handoff ack rate ───
  sessions=${SESSION_COUNT[$agent]:-0}
  s=5
  [ "$sessions" -gt 0 ] && s=$((s + 2))
  [ "$sessions" -gt 3 ] && s=$((s + 2))
  if [ "$LEDGER_HANDOFFS_SENT" -gt 0 ]; then
    ack_pct=$((LEDGER_HANDOFFS_ACKED * 100 / LEDGER_HANDOFFS_SENT))
    [ "$ack_pct" -ge 80 ] && s=$((s + 1))
    [ "$ack_pct" -lt 50 ] && s=$((s - 2))
  fi
  SCORES["${agent}_I04"]=$(clamp $s)
  REASONS["${agent}_I04"]="${sessions} sessions, handoffs ${LEDGER_HANDOFFS_ACKED}/${LEDGER_HANDOFFS_SENT}"

  # ─── I05 RELIABLE: Completion + context stability + model stability ───
  s=5
  r=""
  if [ "$LEDGER_TOTAL" -gt 0 ]; then
    comp_pct=$((LEDGER_COMPLETED * 100 / LEDGER_TOTAL))
    [ "$comp_pct" -ge 80 ] && s=$((s + 2)) && r="completion ${comp_pct}%"
    [ "$comp_pct" -lt 40 ] && s=$((s - 2)) && r="completion ${comp_pct}% (low)"
  fi
  pct=${CTX_PCT[$agent]:-0}
  [ "$pct" -lt 50 ] && s=$((s + 1)) && r="${r:+$r, }headroom"
  [ "$pct" -gt 85 ] && s=$((s - 2)) && r="${r:+$r, }overloaded ${pct}%"
  errs=${MODEL_ERRORS[$agent]:-0}
  [ "$errs" -eq 0 ] && s=$((s + 1)) && r="${r:+$r, }no model errors"
  [ "$errs" -gt 3 ] && s=$((s - 1)) && r="${r:+$r, }${errs} errors"
  [ -z "$r" ] && r="baseline"
  SCORES["${agent}_I05"]=$(clamp $s)
  REASONS["${agent}_I05"]="$r"

  # ─── I06 EFFICIENT: Context usage (lower = more efficient) ───
  pct=${CTX_PCT[$agent]:-0}
  s=$(pct_to_inverse_score $pct)
  SCORES["${agent}_I06"]=$(clamp $s)
  REASONS["${agent}_I06"]="context ${pct}%"

  # ─── I07 RESOURCEFUL: Skills + SOUL + memory access ───
  skills=${SKILL_COUNT[$agent]:-0}
  soul=${SOUL_LINES[$agent]:-0}
  s=5
  [ "$skills" -gt 0 ] && s=$((s + 2))
  [ "${CTX_PCT[$agent]:-0}" -lt 70 ] && s=$((s + 1))
  [ "$soul" -gt 0 ] && s=$((s + 1))
  [ "${HAS_MEMORY_MD[$agent]}" = "true" ] && s=$((s + 1))
  SCORES["${agent}_I07"]=$(clamp $s)
  REASONS["${agent}_I07"]="${skills} skills, SOUL ${soul}L, MEMORY.md:${HAS_MEMORY_MD[$agent]}"

  # ─── I08 RESILIENT: Fallback model + error recovery ───
  s=5
  [ "${HAS_FALLBACK[$agent]}" = "true" ] && s=$((s + 3))
  errs=${MODEL_ERRORS[$agent]:-0}
  [ "$errs" -eq 0 ] && s=$((s + 2))
  [ "$errs" -gt 5 ] && s=$((s - 3))
  SCORES["${agent}_I08"]=$(clamp $s)
  REASONS["${agent}_I08"]="fallback:${HAS_FALLBACK[$agent]}, errors:$errs"

  # ─── I09 GROWING: Skills investment + SOUL depth ───
  skills=${SKILL_COUNT[$agent]:-0}
  soul=${SOUL_LINES[$agent]:-0}
  s=5
  [ "$skills" -gt 2 ] && s=$((s + 2))
  [ "$soul" -gt 80 ] && s=$((s + 2))
  [ "$skills" -eq 0 ] && [ "$soul" -lt 30 ] && s=2
  SCORES["${agent}_I09"]=$(clamp $s)
  REASONS["${agent}_I09"]="${skills} skills, SOUL ${soul}L"

  # ─── I10 CONNECTED: Can reach other agents + has sessions ───
  sessions=${SESSION_COUNT[$agent]:-0}
  s=5
  [ "$sessions" -gt 0 ] && s=$((s + 2))
  # Captain scored on specialist reach
  if [ "$agent" = "main" ]; then
    active=0
    for spec in spec-dev spec-projects spec-github spec-research spec-security spec-ops spec-design spec-systems spec-comms; do
      [ "${SESSION_COUNT[$spec]:-0}" -gt 0 ] && active=$((active + 1))
    done
    pct=$((active * 100 / 9))
    s=$(pct_to_score $pct)
    REASONS["${agent}_I10"]="${active}/9 specialists active"
  else
    [ "$sessions" -eq 0 ] && s=3
    [ "$sessions" -gt 3 ] && s=$((s + 2))
    REASONS["${agent}_I10"]="${sessions} sessions"
  fi
  SCORES["${agent}_I10"]=$(clamp $s)

  # ─── I11 TRUSTED: Cumulative reliability (completion + handoff + stability) ───
  s=5; r=""
  if [ "$LEDGER_TOTAL" -gt 0 ]; then
    comp_pct=$((LEDGER_COMPLETED * 100 / LEDGER_TOTAL))
    [ "$comp_pct" -ge 80 ] && s=$((s + 2)) && r="completion ${comp_pct}%"
    [ "$comp_pct" -lt 40 ] && s=$((s - 2)) && r="completion ${comp_pct}% (low)"
  fi
  if [ "$LEDGER_HANDOFFS_SENT" -gt 0 ]; then
    ack_pct=$((LEDGER_HANDOFFS_ACKED * 100 / LEDGER_HANDOFFS_SENT))
    [ "$ack_pct" -ge 90 ] && s=$((s + 1)) && r="${r:+$r, }handoffs ${ack_pct}%"
    [ "$ack_pct" -lt 50 ] && s=$((s - 2)) && r="${r:+$r, }handoffs ${ack_pct}% (bad)"
  fi
  pct=${CTX_PCT[$agent]:-0}
  [ "$pct" -lt 50 ] && s=$((s + 1)) && r="${r:+$r, }headroom"
  [ "$pct" -gt 85 ] && s=$((s - 2)) && r="${r:+$r, }overloaded"
  errs=${MODEL_ERRORS[$agent]:-0}
  [ "$errs" -eq 0 ] && s=$((s + 1)) && r="${r:+$r, }stable model"
  [ -z "$r" ] && r="baseline"
  SCORES["${agent}_I11"]=$(clamp $s)
  REASONS["${agent}_I11"]="$r"

  # ─── I12 AWARE: Has heartbeat + IDENTITY.md + context not maxed ───
  s=5
  [ "${HAS_HEARTBEAT[$agent]}" = "true" ] && s=$((s + 2))
  [ "${HAS_IDENTITY_MD[$agent]}" = "true" ] && s=$((s + 1))
  pct=${CTX_PCT[$agent]:-0}
  [ "$pct" -gt 85 ] && s=$((s - 2))  # Can't be aware if overloaded
  [ "$pct" -lt 50 ] && s=$((s + 1))
  soul=${SOUL_LINES[$agent]:-0}
  [ "$soul" -gt 50 ] && s=$((s + 1))
  SCORES["${agent}_I12"]=$(clamp $s)
  REASONS["${agent}_I12"]="heartbeat:${HAS_HEARTBEAT[$agent]}, IDENTITY:${HAS_IDENTITY_MD[$agent]}, ctx:${pct}%"

  # ─── I13 OBSERVABLE: Health buffer freshness + load tracking + session data ───
  s=5
  [ "$buffer_age_hrs" -lt 24 ] && s=$((s + 2))
  [ "$buffer_age_hrs" -lt 6 ] && s=$((s + 1))
  [ "$buffer_age_hrs" -gt 48 ] && s=$((s - 2))
  [ -f "$LOG_DIR/agent-load-history.jsonl" ] && s=$((s + 1))
  sessions=${SESSION_COUNT[$agent]:-0}
  [ "$sessions" -gt 0 ] && s=$((s + 1))  # Session data exists = observable
  SCORES["${agent}_I13"]=$(clamp $s)
  REASONS["${agent}_I13"]="buffer ${buffer_age_hrs}h old, load tracking:$([ -f "$LOG_DIR/agent-load-history.jsonl" ] && echo "yes" || echo "no")"

  # ─── I14 ADAPTIVE: Intent tags present + skills growing ───
  tags=${INTENT_TAG_COUNT[$agent]:-0}
  skills=${SKILL_COUNT[$agent]:-0}
  s=5
  [ "$tags" -gt 0 ] && s=$((s + 2))
  [ "$tags" -ge 5 ] && s=$((s + 2))
  [ "$skills" -gt 3 ] && s=$((s + 1))
  [ "$tags" -eq 0 ] && s=$((s - 1))  # Not yet tagged = not yet adaptive
  SCORES["${agent}_I14"]=$(clamp $s)
  REASONS["${agent}_I14"]="${tags} intent tags, ${skills} skills"

  # ─── I15 RECOVERABLE: Fallback model + session maintenance cron ───
  s=5
  [ "${HAS_FALLBACK[$agent]}" = "true" ] && s=$((s + 2))
  # Session maintenance cron exists?
  cron_exists=$(crontab -l 2>/dev/null | grep -c "session-maintenance" || echo 0)
  [ "$cron_exists" -gt 0 ] && s=$((s + 2))
  errs=${MODEL_ERRORS[$agent]:-0}
  [ "$errs" -eq 0 ] && s=$((s + 1))
  SCORES["${agent}_I15"]=$(clamp $s)
  REASONS["${agent}_I15"]="fallback:${HAS_FALLBACK[$agent]}, session-maint cron:$([ "$cron_exists" -gt 0 ] && echo "yes" || echo "no")"

  # ─── I16 SECURE: Config permissions + Security Agent active ───
  s=5
  [ "$config_perms" = "600" ] && s=$((s + 2))
  [ "$config_perms" = "644" ] && s=$((s + 1))
  [ "$env_perms" = "600" ] && s=$((s + 1))
  # Security agent has sessions = actively watching
  sec_sessions=${SESSION_COUNT[spec-security]:-0}
  [ "$sec_sessions" -gt 0 ] && s=$((s + 1))
  # Agent itself has SOUL boundaries (knows what NOT to do)
  nots=${SOUL_BOUNDARIES[$agent]:-0}
  [ "$nots" -gt 0 ] && s=$((s + 1))
  SCORES["${agent}_I16"]=$(clamp $s)
  REASONS["${agent}_I16"]="config:$config_perms, .env:$env_perms, sec-agent sessions:$sec_sessions"

  # ─── I17 AUTONOMOUS: Has skills + low error rate + not overloaded ───
  skills=${SKILL_COUNT[$agent]:-0}
  pct=${CTX_PCT[$agent]:-0}
  errs=${MODEL_ERRORS[$agent]:-0}
  s=5
  [ "$skills" -ge 3 ] && s=$((s + 2))
  [ "$pct" -lt 50 ] && s=$((s + 1))
  [ "$errs" -eq 0 ] && s=$((s + 1))
  [ "${HAS_FALLBACK[$agent]}" = "true" ] && s=$((s + 1))
  [ "$skills" -eq 0 ] && s=2
  SCORES["${agent}_I17"]=$(clamp $s)
  REASONS["${agent}_I17"]="${skills} skills, ctx ${pct}%, errors:$errs"

  # ─── I18 INFORMED: Shared memory quality + staleness (propagates to all) ───
  s=5
  ir=""
  [ "$total_charts" -ge 200 ] && s=$((s + 3)) || { [ "$total_charts" -ge 100 ] && s=$((s + 2)); } || { [ "$total_charts" -ge 40 ] && s=$((s + 1)); }
  ir="${total_charts} charts"
  [ "$error_charts" -ge 5 ] && s=$((s + 1)) && ir="${ir}, ${error_charts} error charts"
  [ "$vision_charts" -ge 2 ] && s=$((s + 1)) && ir="${ir}, ${vision_charts} vision charts"
  # Staleness penalty: stale entries degrade Informed
  [ "$stale_chart_count" -gt 50 ] && s=$((s - 2)) && ir="${ir}, ${stale_chart_count} stale (high)"
  [ "$stale_chart_count" -gt 20 ] && [ "$stale_chart_count" -le 50 ] && s=$((s - 1)) && ir="${ir}, ${stale_chart_count} stale"
  [ "$stale_chart_count" -le 5 ] && [ "$stale_chart_count" -ge 0 ] && s=$((s + 1)) && ir="${ir}, low staleness"
  SCORES["${agent}_I18"]=$(clamp $s)
  REASONS["${agent}_I18"]="$ir"

  # ─── I19 COHERENT: Internal consistency — workspace files, intent awareness, propagation ───
  soul=${SOUL_LINES[$agent]:-0}
  s=5; r=""
  [ "$soul" -gt 30 ] && s=$((s + 1))
  [ "${HAS_TOOLS_MD[$agent]}" = "true" ] && s=$((s + 1)) && r="TOOLS.md"
  [ "${HAS_MEMORY_MD[$agent]}" = "true" ] && s=$((s + 1)) && r="${r:+$r, }MEMORY.md"
  [ "${HAS_IDENTITY_MD[$agent]}" = "true" ] && s=$((s + 1)) && r="${r:+$r, }IDENTITY.md"
  soul_has_intent=$(grep -cl "intent-framework-complete" "$(agent_ws "$agent")/SOUL.md" 2>/dev/null | wc -l)
  [ "$soul_has_intent" -gt 0 ] && s=$((s + 1)) && r="${r:+$r, }intent-aware"
  [ "$soul_has_intent" -eq 0 ] && s=$((s - 1)) && r="${r:+$r, }no intent ref"
  [ "$soul" -eq 0 ] && s=1
  SCORES["${agent}_I19"]=$(clamp $s)
  REASONS["${agent}_I19"]="${r:-baseline}"

done

# ═══════════════════════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════════════════════

NUM_INTENTS=19

if [ "$MODE" = "--json" ]; then
  echo "{"
  echo "  \"timestamp\": \"$TIMESTAMP\","
  echo "  \"framework\": \"I01-I19 v4 + PTV\","
  echo "  \"agents\": {"
  for i in "${!AGENTS[@]}"; do
    agent="${AGENTS[$i]}"
    name="${AGENT_NAMES[$i]}"
    comma=","
    [ "$i" -eq $((${#AGENTS[@]} - 1)) ] && comma=""
    sum=0
    for id in "${INTENT_IDS[@]}"; do
      sum=$((sum + ${SCORES["${agent}_${id}"]:-0}))
    done
    avg=$((sum / NUM_INTENTS))
    echo "    \"$agent\": {\"name\":\"$name\",\"avg\":$avg,\"context_pct\":${CTX_PCT[$agent]:-0},\"skills\":${SKILL_COUNT[$agent]:-0},\"sessions\":${SESSION_COUNT[$agent]:-0}}${comma}"
  done
  echo "  }"
  echo "}"
else
  echo "+=================================================================+"
  echo "|     AGENT SATISFACTION REPORT -- $TIMESTAMP     |"
  echo "+=================================================================+"
  echo ""
  echo "  Two dimensions: Intent [I##] (how well) + Purpose Toward Vision [P##] (why)"
  echo "  EXECUTION(Accurate,Competent,Reliable,Efficient,Resourceful)"
  echo "  RESILIENCE(Resilient,Trusted,Recoverable) GROWTH(Growing,Adaptive,Autonomous,Informed)"
  echo "  CONNECTION(Understood,Responsive,Connected) AWARENESS(Aware,Observable,Coherent,Secure)"
  echo ""

  for i in "${!AGENTS[@]}"; do
    agent="${AGENTS[$i]}"
    name="${AGENT_NAMES[$i]}"

    # Skip if filtering to single agent
    [ -n "$FILTER_AGENT" ] && [ "$FILTER_AGENT" != "$agent" ] && continue

    pct=${CTX_PCT[$agent]:-0}
    sum=0
    for id in "${INTENT_IDS[@]}"; do
      sum=$((sum + ${SCORES["${agent}_${id}"]:-0}))
    done
    avg=$((sum / NUM_INTENTS))

    state="ok"
    [ "$pct" -gt 70 ] && state="STRAINED"
    [ "$pct" -gt 85 ] && state="OVERLOADED"

    printf "+-- %-14s (%-12s) -- avg: %d/10 -- ctx: %d%% %s\n" "$name" "$agent" "$avg" "$pct" "$state"

    for j in "${!INTENT_IDS[@]}"; do
      id="${INTENT_IDS[$j]}"
      iname="${INTENT_NAMES[$j]}"
      s=${SCORES["${agent}_${id}"]:-0}
      r="${REASONS["${agent}_${id}"]:-}"
      bar=""
      for ((b=0; b<s; b++)); do bar="${bar}#"; done
      for ((b=s; b<10; b++)); do bar="${bar}."; done
      printf "|  %-12s [%-3s] [%s] %2d  %s\n" "$iname" "$id" "$bar" "$s" "$r"
    done
    echo "+------------------------------------------------------------------"
    echo ""
  done

  # System summary
  echo "+-- SYSTEM SUMMARY"
  echo "|"
  # Compute fleet average
  fleet_sum=0
  fleet_count=0
  for agent in "${AGENTS[@]}"; do
    agent_sum=0
    for id in "${INTENT_IDS[@]}"; do
      agent_sum=$((agent_sum + ${SCORES["${agent}_${id}"]:-0}))
    done
    agent_avg=$((agent_sum / NUM_INTENTS))
    fleet_sum=$((fleet_sum + agent_avg))
    fleet_count=$((fleet_count + 1))
  done
  fleet_avg=$((fleet_sum / fleet_count))
  echo "|  Fleet average: $fleet_avg/10"
  echo "|  Agents: ${#AGENTS[@]}"
  echo "|  Total skills: $(for a in "${AGENTS[@]}"; do echo "${SKILL_COUNT[$a]:-0}"; done | paste -sd+ | bc)"
  echo "|  Chartroom: $total_charts entries"
  echo "|  Health buffer: ${buffer_age_hrs}h since last entry"
  echo "|  Stale charts: $stale_chart_count"
  echo "|"

  # Intent group averages
  for group_name in "EXECUTION" "RESILIENCE" "GROWTH" "CONNECTION" "AWARENESS"; do
    case $group_name in
      EXECUTION)  group_ids=(I01 I03 I05 I06 I07) ;;
      RESILIENCE) group_ids=(I08 I11 I15) ;;
      GROWTH)     group_ids=(I09 I14 I17 I18) ;;
      CONNECTION) group_ids=(I02 I04 I10) ;;
      AWARENESS)  group_ids=(I12 I13 I16 I19) ;;
    esac
    gsum=0; gcount=0
    for agent in "${AGENTS[@]}"; do
      for id in "${group_ids[@]}"; do
        gsum=$((gsum + ${SCORES["${agent}_${id}"]:-0}))
        gcount=$((gcount + 1))
      done
    done
    gavg=$((gsum / gcount))
    printf "|  %-12s avg: %d/10  (%s)\n" "$group_name" "$gavg" "${group_ids[*]}"
  done
  echo "+------------------------------------------------------------------"
fi
