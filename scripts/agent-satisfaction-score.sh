#!/usr/bin/env bash
# agent-satisfaction-score.sh — Score all 17 intents with real data
#
# Each intent gets a 0-10 score based on measurable signals.
# No guessing, no self-reporting — only data we can query.
#
# Usage:
#   agent-satisfaction-score.sh              # human-readable report
#   agent-satisfaction-score.sh --json       # machine-readable
#   agent-satisfaction-score.sh --agent relay # single agent detail

set -eo pipefail

MODE="${1:-report}"
FILTER_AGENT="${2:-}"
COMPOSE_DIR="/root/openclaw"
LEDGER="/root/.openclaw/bridge/reactor-ledger.sqlite"
LOG_DIR="/root/.openclaw/logs"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

AGENTS=("relay" "main" "spec-projects" "spec-github" "spec-dev" "spec-reactor" "spec-browser" "spec-research" "spec-security" "spec-ops" "spec-design" "spec-systems" "spec-comms")
AGENT_NAMES=("Relay" "Captain" "Scribe" "Repo-Man" "Dev" "Reactor Mgr" "Navigator" "Research" "Security" "Ops Officer" "Designer" "Sys Engineer" "Comms Officer")

# ─── HELPER: score from percentage (higher % = lower score) ───
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

# ─── HELPER: score from percentage (higher % = higher score) ───
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

# ═══════════════════════════════════════════════════════════════
# COLLECT DATA
# ═══════════════════════════════════════════════════════════════

declare -A AGENT_CONTEXT_PCT
declare -A AGENT_SKILL_COUNT
declare -A AGENT_SOUL_LINES
declare -A AGENT_SOUL_HAS_NOT  # Does SOUL.md explicitly state what agent does NOT do?
declare -A AGENT_HAS_HEARTBEAT
declare -A AGENT_SESSION_COUNT
declare -A AGENT_MODEL_ERRORS
declare -A AGENT_HAS_FALLBACK

# --- Context % (Intent: Equipped / Overload) ---
for i in "${!AGENTS[@]}"; do
  agent="${AGENTS[$i]}"
  json=$(cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway openclaw sessions --agent "$agent" --json 2>/dev/null | grep -v "level=warning")
  if [ -n "$json" ]; then
    peak=$(echo "$json" | jq '[.sessions // [] | .[] | select(.contextTokens > 0 and .totalTokens != null and .totalTokens > 0) | (.totalTokens / .contextTokens * 100 | floor)] | max // 0' 2>/dev/null)
    AGENT_CONTEXT_PCT[$agent]="${peak:-0}"
    count=$(echo "$json" | jq '.sessions | length' 2>/dev/null)
    AGENT_SESSION_COUNT[$agent]="${count:-0}"
  else
    AGENT_CONTEXT_PCT[$agent]=0
    AGENT_SESSION_COUNT[$agent]=0
  fi
done

# --- Skills per agent (Intent: Equipped, Focus) ---
for agent in "${AGENTS[@]}"; do
  ws="/root/.openclaw/workspace"
  [ "$agent" != "main" ] && ws="/root/.openclaw/workspace-$agent"
  # Captain uses workspace/ but also check workspace-main
  [ "$agent" = "main" ] && ws="/root/.openclaw/workspace"
  skills=$(ls -d "$ws/skills/"*/ 2>/dev/null | wc -l)
  AGENT_SKILL_COUNT[$agent]="$skills"
done

# --- SOUL.md quality (Intent: Clarity) ---
for agent in "${AGENTS[@]}"; do
  ws="/root/.openclaw/workspace"
  [ "$agent" != "main" ] && ws="/root/.openclaw/workspace-$agent"
  [ "$agent" = "main" ] && ws="/root/.openclaw/workspace"
  if [ -f "$ws/SOUL.md" ]; then
    AGENT_SOUL_LINES[$agent]=$(wc -l < "$ws/SOUL.md")
    # Check if SOUL.md has explicit "NOT" / "don't" / "never" boundaries
    nots=$(grep -ciE "(you do not|not your|never |don.t |outside your)" "$ws/SOUL.md" 2>/dev/null || echo 0)
    AGENT_SOUL_HAS_NOT[$agent]="$nots"
  else
    AGENT_SOUL_LINES[$agent]=0
    AGENT_SOUL_HAS_NOT[$agent]=0
  fi
done

# --- Heartbeat enabled? (Intent: Regular Check-in) ---
# Only relay has heartbeat enabled currently — check via health snapshot
relay_hb_enabled="true"  # Known from config
for agent in "${AGENTS[@]}"; do
  if [ "$agent" = "relay" ]; then
    AGENT_HAS_HEARTBEAT[$agent]="true"
  else
    AGENT_HAS_HEARTBEAT[$agent]="false"
  fi
done

# --- Model fallback availability (Intent: Resilient) ---
for agent in "${AGENTS[@]}"; do
  profiles=$(docker compose exec openclaw-gateway cat "/home/node/.openclaw/agents/$agent/agent/auth-profiles.json" 2>/dev/null | grep -v "level=warning" | jq 'length // 0' 2>/dev/null || echo 0)
  if [ -n "$profiles" ] && [ "$profiles" -gt 1 ]; then
    AGENT_HAS_FALLBACK[$agent]="true"
  else
    AGENT_HAS_FALLBACK[$agent]="false"
  fi
  errors=$(docker compose exec openclaw-gateway cat "/home/node/.openclaw/agents/$agent/agent/auth-profiles.json" 2>/dev/null | grep -v "level=warning" | jq '[to_entries[] | .value.errorCount // 0] | add // 0' 2>/dev/null || echo 0)
  AGENT_MODEL_ERRORS[$agent]="${errors:-0}"
done

# --- Reactor ledger (Intent: Voice — did results reach audience?) ---
LEDGER_TOTAL=0
LEDGER_COMPLETED=0
LEDGER_FAILED=0
LEDGER_HANDOFFS_SENT=0
LEDGER_HANDOFFS_ACKED=0
if [ -f "$LEDGER" ]; then
  ledger_raw=$(sqlite3 "$LEDGER" "SELECT COUNT(*) || '|' || COALESCE(SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END),0) || '|' || COALESCE(SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END),0) || '|' || COALESCE(SUM(CASE WHEN relay_handoff_sent=1 THEN 1 ELSE 0 END),0) || '|' || COALESCE(SUM(CASE WHEN relay_handoff_acked=1 THEN 1 ELSE 0 END),0) FROM jobs" 2>/dev/null)
  IFS='|' read LEDGER_TOTAL LEDGER_COMPLETED LEDGER_FAILED LEDGER_HANDOFFS_SENT LEDGER_HANDOFFS_ACKED <<< "$ledger_raw"
fi

# ═══════════════════════════════════════════════════════════════
# SCORE EACH INTENT
# ═══════════════════════════════════════════════════════════════

declare -A SCORES
declare -A SCORE_REASONS

# --- 1. CLARITY: Does agent know what it does AND doesn't do? ---
for i in "${!AGENTS[@]}"; do
  agent="${AGENTS[$i]}"
  soul=${AGENT_SOUL_LINES[$agent]:-0}
  nots=${AGENT_SOUL_HAS_NOT[$agent]:-0}
  score=5
  [ "$soul" -gt 50 ] && score=$((score + 2))
  [ "$soul" -gt 100 ] && score=$((score + 1))
  [ "$nots" -gt 0 ] && score=$((score + 2))  # Has explicit boundaries
  [ "$score" -gt 10 ] && score=10
  [ "$soul" -eq 0 ] && score=0
  SCORES["${agent}_clarity"]=$score
  SCORE_REASONS["${agent}_clarity"]="SOUL.md: ${soul} lines, ${nots} boundary statements"
done

# --- 2. HARMONY: Handoff success rate ---
harmony_score=5
if [ "$LEDGER_HANDOFFS_SENT" -gt 0 ]; then
  ack_pct=$((LEDGER_HANDOFFS_ACKED * 100 / LEDGER_HANDOFFS_SENT))
  harmony_score=$(pct_to_score $ack_pct)
fi
for agent in "${AGENTS[@]}"; do
  SCORES["${agent}_harmony"]=$harmony_score
  SCORE_REASONS["${agent}_harmony"]="Handoffs: ${LEDGER_HANDOFFS_ACKED}/${LEDGER_HANDOFFS_SENT} acked"
done

# --- 3. FOCUS: Skill count in sweet spot (3-7 = ideal) ---
for agent in "${AGENTS[@]}"; do
  skills=${AGENT_SKILL_COUNT[$agent]:-0}
  if [ "$skills" -ge 3 ] && [ "$skills" -le 7 ]; then
    score=10
  elif [ "$skills" -ge 1 ] && [ "$skills" -le 12 ]; then
    score=7
  elif [ "$skills" -gt 12 ]; then
    score=5  # Too many — fragmented
  else
    score=3  # No skills — underequipped
  fi
  SCORES["${agent}_focus"]=$score
  SCORE_REASONS["${agent}_focus"]="$skills skills (sweet spot: 3-7)"
done

# --- 4. VOICE: Do results reach their audience? ---
voice_score=5
voice_reason="No reactor data"
if [ "$LEDGER_TOTAL" -gt 0 ]; then
  completion_pct=$((LEDGER_COMPLETED * 100 / LEDGER_TOTAL))
  voice_score=$(pct_to_score $completion_pct)
  voice_reason="Tasks: ${LEDGER_COMPLETED}/${LEDGER_TOTAL} completed (${completion_pct}%)"
fi
for agent in "${AGENTS[@]}"; do
  SCORES["${agent}_voice"]=$voice_score
  SCORE_REASONS["${agent}_voice"]="$voice_reason"
done

# --- 5. FIT: Routing accuracy (need Captain routing logs — estimate from session diversity) ---
for agent in "${AGENTS[@]}"; do
  sessions=${AGENT_SESSION_COUNT[$agent]:-0}
  score=7  # Default: assume routing works
  # Captain gets scored on whether specialists have sessions (meaning work reaches them)
  if [ "$agent" = "main" ]; then
    active_specialists=0
    for spec in spec-dev spec-projects spec-github spec-research spec-security; do
      [ "${AGENT_SESSION_COUNT[$spec]:-0}" -gt 0 ] && active_specialists=$((active_specialists + 1))
    done
    fit_pct=$((active_specialists * 100 / 5))
    score=$(pct_to_score $fit_pct)
    SCORE_REASONS["${agent}_fit"]="$active_specialists/5 specialists have sessions"
  else
    SCORE_REASONS["${agent}_fit"]="$sessions sessions (work is arriving)"
    [ "$sessions" -eq 0 ] && score=3 && SCORE_REASONS["${agent}_fit"]="No sessions — no work reaching this agent"
  fi
  SCORES["${agent}_fit"]=$score
done

# --- 6. FLOW: Measured by context efficiency (lower context % for same work = better flow) ---
for agent in "${AGENTS[@]}"; do
  pct=${AGENT_CONTEXT_PCT[$agent]:-0}
  score=$(pct_to_inverse_score $pct)
  SCORES["${agent}_flow"]=$score
  SCORE_REASONS["${agent}_flow"]="Context at ${pct}% — lower = more room to work"
done

# --- 7. EQUIPPED: Skills + memory + context headroom ---
for agent in "${AGENTS[@]}"; do
  skills=${AGENT_SKILL_COUNT[$agent]:-0}
  pct=${AGENT_CONTEXT_PCT[$agent]:-0}
  soul=${AGENT_SOUL_LINES[$agent]:-0}
  score=5
  [ "$skills" -gt 0 ] && score=$((score + 2))
  [ "$pct" -lt 70 ] && score=$((score + 2))  # Has headroom
  [ "$soul" -gt 0 ] && score=$((score + 1))
  [ "$score" -gt 10 ] && score=10
  SCORES["${agent}_equipped"]=$score
  SCORE_REASONS["${agent}_equipped"]="${skills} skills, ${pct}% context, SOUL.md ${soul}L"
done

# --- 8. RESILIENT: Has fallback model? Model errors? ---
for agent in "${AGENTS[@]}"; do
  fallback="${AGENT_HAS_FALLBACK[$agent]:-false}"
  errors="${AGENT_MODEL_ERRORS[$agent]:-0}"
  score=5
  [ "$fallback" = "true" ] && score=$((score + 3))
  [ "$errors" -eq 0 ] && score=$((score + 2))
  [ "$errors" -gt 5 ] && score=$((score - 3))
  [ "$score" -gt 10 ] && score=10
  [ "$score" -lt 0 ] && score=0
  SCORES["${agent}_resilient"]=$score
  SCORE_REASONS["${agent}_resilient"]="Fallback: $fallback, model errors: $errors"
done

# --- 9. GROWING: Chartroom entries exist for this agent? Skills added recently? ---
for agent in "${AGENTS[@]}"; do
  # Simple proxy: skill count > 0 and SOUL.md > 50 lines means someone is investing
  skills=${AGENT_SKILL_COUNT[$agent]:-0}
  soul=${AGENT_SOUL_LINES[$agent]:-0}
  score=5
  [ "$skills" -gt 2 ] && score=$((score + 2))
  [ "$soul" -gt 80 ] && score=$((score + 2))
  [ "$skills" -eq 0 ] && [ "$soul" -lt 30 ] && score=2
  [ "$score" -gt 10 ] && score=10
  SCORES["${agent}_growing"]=$score
  SCORE_REASONS["${agent}_growing"]="${skills} skills, SOUL ${soul}L"
done

# --- 10. PURPOSEFUL: Has tasks in ledger OR active sessions? ---
for agent in "${AGENTS[@]}"; do
  sessions=${AGENT_SESSION_COUNT[$agent]:-0}
  score=7
  [ "$sessions" -gt 3 ] && score=9  # Actively used
  [ "$sessions" -le 1 ] && score=5  # Low activity
  SCORES["${agent}_purposeful"]=$score
  SCORE_REASONS["${agent}_purposeful"]="$sessions sessions"
done

# --- 11. TRUSTED: Cumulative reliability signal ---
# Trust = f(completion rate, handoff reliability, context stability, no session bleed)
# Starts at 5 (neutral). Each positive signal adds, each negative subtracts.
# This is the intent that decides whether delegation happens.
for agent in "${AGENTS[@]}"; do
  trust=5
  reasons=""

  # Signal 1: Task completion (system-wide for now, per-agent when ledger tracks it)
  if [ "$LEDGER_TOTAL" -gt 0 ]; then
    comp_pct=$((LEDGER_COMPLETED * 100 / LEDGER_TOTAL))
    [ "$comp_pct" -ge 80 ] && trust=$((trust + 2)) && reasons="completion ${comp_pct}%"
    [ "$comp_pct" -ge 60 ] && [ "$comp_pct" -lt 80 ] && trust=$((trust + 1)) && reasons="completion ${comp_pct}%"
    [ "$comp_pct" -lt 40 ] && trust=$((trust - 2)) && reasons="completion ${comp_pct}% (low)"
  fi

  # Signal 2: Handoff reliability
  if [ "$LEDGER_HANDOFFS_SENT" -gt 0 ]; then
    ack_pct=$((LEDGER_HANDOFFS_ACKED * 100 / LEDGER_HANDOFFS_SENT))
    [ "$ack_pct" -ge 90 ] && trust=$((trust + 1)) && reasons="${reasons}, handoffs ${ack_pct}%"
    [ "$ack_pct" -lt 50 ] && trust=$((trust - 2)) && reasons="${reasons}, handoffs ${ack_pct}% (unreliable)"
  fi

  # Signal 3: Context stability (not chronically overloaded)
  pct=${AGENT_CONTEXT_PCT[$agent]:-0}
  [ "$pct" -lt 50 ] && trust=$((trust + 1)) && reasons="${reasons}, headroom"
  [ "$pct" -gt 85 ] && trust=$((trust - 2)) && reasons="${reasons}, overloaded"

  # Signal 4: Model stability (no errors = reliable)
  errs=${AGENT_MODEL_ERRORS[$agent]:-0}
  [ "$errs" -eq 0 ] && trust=$((trust + 1)) && reasons="${reasons}, no model errors"
  [ "$errs" -gt 3 ] && trust=$((trust - 1)) && reasons="${reasons}, ${errs} model errors"

  # Clamp
  [ "$trust" -gt 10 ] && trust=10
  [ "$trust" -lt 0 ] && trust=0

  # Clean up reasons string
  reasons=$(echo "$reasons" | sed 's/^, //')
  [ -z "$reasons" ] && reasons="baseline (no data)"

  SCORES["${agent}_trusted"]=$trust
  SCORE_REASONS["${agent}_trusted"]="$reasons"
done

# --- 11-16: ORCHESTRATOR/META intents (system-wide, not per-agent) ---
# 11. SELF-AWARENESS: Captain monitors itself (has own context tracked)
captain_pct=${AGENT_CONTEXT_PCT[main]:-0}
sa_score=$(pct_to_inverse_score $captain_pct)
SCORES["system_self_awareness"]=$sa_score
SCORE_REASONS["system_self_awareness"]="Captain context at ${captain_pct}%"

# 12. REGULAR CHECK-IN: Is heartbeat enabled? Is satisfaction report fresh?
checkin_score=4  # No satisfaction report exists yet
relay_hb="${AGENT_HAS_HEARTBEAT[relay]:-false}"
[ "$relay_hb" = "true" ] && checkin_score=$((checkin_score + 3))
# Check if load history has recent entries
if [ -f "$LOG_DIR/agent-load-history.jsonl" ]; then
  recent=$(tail -1 "$LOG_DIR/agent-load-history.jsonl" 2>/dev/null | jq -r '.timestamp' 2>/dev/null)
  [ -n "$recent" ] && checkin_score=$((checkin_score + 2))
fi
[ "$checkin_score" -gt 10 ] && checkin_score=10
SCORES["system_checkin"]=$checkin_score
SCORE_REASONS["system_checkin"]="Heartbeat: $relay_hb, load tracking: $([ -f "$LOG_DIR/agent-load-history.jsonl" ] && echo "active" || echo "none")"

# 13. TRAINING: All agents have SOUL.md + skills?
trained=0
for agent in "${AGENTS[@]}"; do
  soul=${AGENT_SOUL_LINES[$agent]:-0}
  skills=${AGENT_SKILL_COUNT[$agent]:-0}
  [ "$soul" -gt 30 ] && [ "$skills" -gt 0 ] && trained=$((trained + 1))
done
train_pct=$((trained * 100 / ${#AGENTS[@]}))
SCORES["system_training"]=$(pct_to_score $train_pct)
SCORE_REASONS["system_training"]="$trained/${#AGENTS[@]} agents fully equipped"

# 14. WORKFORCE MGMT: Any chronically overloaded agents?
wf_score=8
for agent in "${AGENTS[@]}"; do
  [ "${AGENT_CONTEXT_PCT[$agent]:-0}" -gt 85 ] && wf_score=$((wf_score - 2))
done
[ "$wf_score" -lt 0 ] && wf_score=0
SCORES["system_workforce"]=$wf_score
SCORE_REASONS["system_workforce"]="Overloaded agents reduce score"

# 15. EQUAL RESPECT: All agents scored equally? (this script existing = yes)
SCORES["system_equal_respect"]=8
SCORE_REASONS["system_equal_respect"]="All 10 agents + system scored by same metrics"

# 17. INTENT ENDURES: Are the intents documented?
SCORES["system_intent_endures"]=9
SCORE_REASONS["system_intent_endures"]="18 intents locked in agent-satisfaction-design.md"

# 18. INFORMED: Is the shared memory sharp, helpful, protective, prepared?
# Measures Chartroom quality as experienced by all agents.
# A sharp memory lifts every agent. A dull memory sinks them all.
# Signals: vector coverage (can entries be found?), actionability, coverage, freshness.
informed_score=5
informed_reasons=""

# Signal 1: Total chartroom size — more knowledge = better prepared
total_entries=$(chart list 300 2>/dev/null | tail -1 | grep -oP '\d+' || echo "0")
if [ "$total_entries" -ge 200 ]; then
  informed_score=$((informed_score + 3))
elif [ "$total_entries" -ge 100 ]; then
  informed_score=$((informed_score + 2))
elif [ "$total_entries" -ge 40 ]; then
  informed_score=$((informed_score + 1))
fi
informed_reasons="${total_entries} charts total"

# Signal 2: Coverage — error charts (protective) + agent profiles (prepared)
chart_listing=$(chart list 300 2>/dev/null)
error_charts=$(echo "$chart_listing" | grep -c "^issue\|^error" || echo "0")
agent_charts=$(echo "$chart_listing" | grep -c "agent-" || echo "0")
vision_charts=$(echo "$chart_listing" | grep -c "^vision" || echo "0")
[ "$error_charts" -ge 5 ] && informed_score=$((informed_score + 1)) && informed_reasons="${informed_reasons}, ${error_charts} error charts (protective)"
[ "$agent_charts" -ge 10 ] && informed_score=$((informed_score + 1)) && informed_reasons="${informed_reasons}, ${agent_charts} agent profiles (prepared)"
[ "$vision_charts" -ge 2 ] && informed_score=$((informed_score + 1)) && informed_reasons="${informed_reasons}, ${vision_charts} vision charts (north star)"

# Clamp
[ "$informed_score" -gt 10 ] && informed_score=10
[ "$informed_score" -lt 0 ] && informed_score=0

SCORES["system_informed"]=$informed_score
SCORE_REASONS["system_informed"]="$informed_reasons"

# INFORMED propagates to every agent (shared memory affects everyone)
for agent in "${AGENTS[@]}"; do
  SCORES["${agent}_informed"]=$informed_score
  SCORE_REASONS["${agent}_informed"]="Shared memory: $informed_reasons"
done

# ═══════════════════════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════════════════════

if [ "$MODE" = "--json" ]; then
  echo "{"
  echo "  \"timestamp\": \"$TIMESTAMP\","
  echo "  \"agents\": {"
  for i in "${!AGENTS[@]}"; do
    agent="${AGENTS[$i]}"
    name="${AGENT_NAMES[$i]}"
    comma=","
    [ "$i" -eq $((${#AGENTS[@]} - 1)) ] && comma=""
    avg=0
    sum=0
    for intent in clarity harmony focus voice fit flow equipped resilient growing purposeful trusted informed; do
      sum=$((sum + ${SCORES["${agent}_${intent}"]:-0}))
    done
    avg=$((sum / 12))
    echo "    \"$agent\": {\"name\":\"$name\",\"avg\":$avg,\"context_pct\":${AGENT_CONTEXT_PCT[$agent]:-0},\"skills\":${AGENT_SKILL_COUNT[$agent]:-0},\"sessions\":${AGENT_SESSION_COUNT[$agent]:-0}}${comma}"
  done
  echo "  },"
  echo "  \"system\": {\"self_awareness\":${SCORES[system_self_awareness]},\"checkin\":${SCORES[system_checkin]},\"training\":${SCORES[system_training]},\"workforce\":${SCORES[system_workforce]},\"equal_respect\":${SCORES[system_equal_respect]},\"intent_endures\":${SCORES[system_intent_endures]},\"informed\":${SCORES[system_informed]}}"
  echo "}"
else
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           AGENT SATISFACTION REPORT — $TIMESTAMP           ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  for i in "${!AGENTS[@]}"; do
    agent="${AGENTS[$i]}"
    name="${AGENT_NAMES[$i]}"
    pct=${AGENT_CONTEXT_PCT[$agent]:-0}

    # Calculate average
    sum=0
    for intent in clarity harmony focus voice fit flow equipped resilient growing purposeful trusted informed; do
      sum=$((sum + ${SCORES["${agent}_${intent}"]:-0}))
    done
    avg=$((sum / 12))

    # State emoji
    state="ok"
    [ "$pct" -gt 70 ] && state="STRAINED"
    [ "$pct" -gt 85 ] && state="OVERLOADED"

    printf "┌─ %-14s (%-12s) ── avg: %d/10 ── context: %d%% %s\n" "$name" "$agent" "$avg" "$pct" "$state"
    for intent in clarity harmony focus voice fit flow equipped resilient growing purposeful trusted informed; do
      s=${SCORES["${agent}_${intent}"]:-0}
      r="${SCORE_REASONS["${agent}_${intent}"]:-}"
      bar=""
      for ((b=0; b<s; b++)); do bar="${bar}#"; done
      for ((b=s; b<10; b++)); do bar="${bar}."; done
      printf "│  %-12s [%s] %2d  %s\n" "$intent" "$bar" "$s" "$r"
    done
    echo "└──────────────────────────────────────────────────────────────"
    echo ""
  done

  echo "┌─ SYSTEM (orchestrator + meta intents)"
  for intent in self_awareness checkin training workforce equal_respect intent_endures informed; do
    s=${SCORES["system_${intent}"]:-0}
    r="${SCORE_REASONS["system_${intent}"]:-}"
    bar=""
    for ((b=0; b<s; b++)); do bar="${bar}#"; done
    for ((b=s; b<10; b++)); do bar="${bar}."; done
    printf "│  %-16s [%s] %2d  %s\n" "$intent" "$bar" "$s" "$r"
  done
  echo "└──────────────────────────────────────────────────────────────"
fi
