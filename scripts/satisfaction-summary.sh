#!/usr/bin/env bash
# satisfaction-summary.sh — One-line fleet satisfaction summary from agent_performance (ops.db).
# Intent: Observable [I13]. Owner: Captain.
#
# FIX 2026-06-01 (B1): previously this grepped a non-existent "satisfaction report" chart and so
# ALWAYS printed "Satisfaction: No report available" (issue #21). It now queries agent_performance
# directly AND is FRESHNESS-AWARE: if the latest scored date is older than 1 day it prefixes STALE
# with the age, because a dead aggregate must never read as a fresh green ("stale green is worse
# than no data"). net_score scale is -10..+10.
#
# DEPENDS ON: ops.db table `agent_performance`, populated by `satisfaction-daily-aggregate.py`
#   (cron 0 6 * * *). If this reports STALE, that scorer cron stopped (it had no cron until
#   2026-06-01 — see chart issue-satisfaction-dashboard-dark-fixed-20260601).
# NOTE: robert/corinne are HUMANS not agents (their agents are Relay/Eoin) — excluded from the fleet
#   average; robert is reported as a separate "Owner dispatch" line. See memory
#   satisfaction-humans-not-agents. Consumed by: sitrep; mirrors the Bridge happiness panel.
set -eo pipefail
DB=/root/.openclaw/ops.db

LATEST=$(sqlite3 "$DB" "SELECT MAX(date) FROM agent_performance;" 2>/dev/null || echo "")
if [ -z "$LATEST" ]; then
  echo "Satisfaction: no agent_performance data (scorer never populated)."
  exit 0
fi

# Humans are NOT agents: 'robert' (his agent is Relay) and 'corinne' (her agent is Eoin) get a row
# for dispatch tracking but must be excluded from fleet AGENT happiness, or they drag the average
# down as 'no-dispatch-data'. (Robert correction, 2026-06-01.)
HUMANS="'robert','corinne'"
read -r AVG AGENTS NEG <<<"$(sqlite3 -separator ' ' "$DB" \
  "SELECT round(avg(net_score),1), count(*), COALESCE(sum(net_score<0),0) FROM agent_performance WHERE date='$LATEST' AND agent NOT IN ($HUMANS);")"
read -r BAGENT BSCORE <<<"$(sqlite3 -separator ' ' "$DB" \
  "SELECT agent, net_score FROM agent_performance WHERE date='$LATEST' AND agent NOT IN ($HUMANS) ORDER BY net_score ASC, agent LIMIT 1;")"

# Freshness gate: flag if the latest scored day is more than a day old.
AGE_DAYS=$(python3 -c "from datetime import date; y,m,d='$LATEST'.split('-'); print((date.today()-date(int(y),int(m),int(d))).days)" 2>/dev/null || echo "?")
PREFIX=""
if [ "$AGE_DAYS" != "?" ] && [ "$AGE_DAYS" -gt 1 ]; then PREFIX="STALE(${AGE_DAYS}d) "; fi

echo "${PREFIX}Satisfaction: fleet ${AVG} (-10..+10) across ${AGENTS} agents. Bottom: ${BAGENT} (${BSCORE}). Negative: ${NEG}. Data ${LATEST}."

# Owner dispatch health — SEPARATE signal, NOT agent happiness. 'robert' is the human (his agent is
# Relay); this reports how well HIS dispatches fared + how often he had to intervene via Bridge.
OWNER_JSON=$(sqlite3 "$DB" "SELECT summary FROM agent_performance WHERE date='$LATEST' AND agent='robert' LIMIT 1;" 2>/dev/null || echo "")
if [ -n "$OWNER_JSON" ]; then
  printf '%s' "$OWNER_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    c = d.get('dispatches_created', 0); s = d.get('dispatches_succeeded', 0)
    f = d.get('dispatches_failed', 0); o = d.get('dispatches_open', 0)
    hi = d.get('human_interventions', 0)
    if c == 0:
        print('Owner dispatch (Robert): no dispatches in window (his agent is Relay).')
    else:
        print(f'Owner dispatch (Robert): {c} created, {s} ok, {f} failed, {o} open; {hi} needed a manual Bridge fix.')
except Exception:
    pass
"
fi
