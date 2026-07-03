#!/bin/bash
# reactor-vitals.sh — one-line host + system vitals for Reactor. Zero LLM cost (pure bash/sqlite).
# Covers: Hostinger throttle state (CPU steal%), perf (load/mem), and "mail" (agent_inbox + notifications).
#   reactor-vitals.sh            -> print one vitals line to stdout
#   reactor-vitals.sh --log FILE -> also append that line to FILE (for perf sampling; no context cost)
set -o pipefail
DB=/root/.openclaw/ops.db

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
read -r l1 l5 l15 _ < /proc/loadavg

# CPU steal% (Hostinger throttle indicator) + idle%, from a 1s /proc/stat delta (robust).
_snap() { awk '/^cpu /{print $2,$3,$4,$5,$6,$7,$8,$9}' /proc/stat; }
read -r u1 n1 s1 i1 w1 q1 x1 t1 <<< "$(_snap)"
sleep 1
read -r u2 n2 s2 i2 w2 q2 x2 t2 <<< "$(_snap)"
dtot=$(( (u2+n2+s2+i2+w2+q2+x2+t2) - (u1+n1+s1+i1+w1+q1+x1+t1) ))
cpu=$(awk -v dst=$(( t2 - t1 )) -v did=$(( i2 - i1 )) -v tot="$dtot" 'BEGIN{ if(tot>0) printf "steal=%.1f%% idle=%.1f%%", 100*dst/tot, 100*did/tot; else printf "steal=?%% idle=?%%" }')

memav=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
gw=$(docker inspect --format '{{.State.Status}}' openclaw-openclaw-gateway-1 2>/dev/null || echo unknown)
mail=$(sqlite3 -readonly "$DB" "SELECT COUNT(*) FROM agent_inbox WHERE read=0 AND target_agent IN ('reactor','Reactor','main','reactor-manager');" 2>/dev/null || echo '?')
notif=$(sqlite3 -readonly "$DB" "SELECT COUNT(*) FROM notifications WHERE delivered=0;" 2>/dev/null || echo '?')

line="$ts load=$l1/$l5/$l15 $cpu memavail=${memav}M gw=$gw mail=$mail notif=$notif"
echo "$line"
if [ "$1" = "--log" ] && [ -n "$2" ]; then echo "$line" >> "$2"; fi
