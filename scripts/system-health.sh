#!/usr/bin/env bash
# system-health.sh — Golden script for Relay's system-health skill
#
# PURPOSE: Gather system health from 6 sources, output JSON summary.
# Runs on HOST via host-ops-executor (needs systemctl, docker compose).
# Relay reads the JSON and renders a tiered response:
#   - overall_status "healthy" → compact text, no buttons
#   - overall_status "issues_found" → text + fix buttons per issue
#
# USAGE:
#   bash /root/.openclaw/scripts/system-health.sh
#   # Returns JSON to stdout. Always exits 0 (issues reported in output).
#
# WHAT EACH CHECK DOES:
#   1. Gateway: runs `openclaw health` inside the container to get event loop
#      lag, CPU, and degradation status. Event loop lag >5s is normal under
#      load but >15s suggests the gateway is struggling.
#   2. Stability: reads stability-state.json which the stability-monitor
#      writes. States: stable, degraded, quarantined.
#   3. Disk: df on root partition. Alert at 85% — Docker images + logs grow.
#   4. Memory: free on host. Alert at 85% — container + host-ops compete.
#   5. Services: systemd status of host-ops-executor and bridge-dev.
#      If either is down, Relay can't dispatch work or serve the web UI.
#   6. Tasks: recent ops.db task health. >3 blocked tasks in 24h means
#      something is stuck in the pipeline.
#
# ERROR RECOVERY:
#   If this script fails to run at all, the host-ops handler returns
#   status "blocked" — Relay should tell Robert: "Health check failed.
#   The script itself had an error, not the system."
#
# HISTORY:
#   Created 2026-05-19 during Relay overhaul session.
#   Replaces ad-hoc health checks scattered across crons.

set -euo pipefail

issues=()

# ---------- 1. Container / Gateway Health ----------
# `openclaw health` outputs lines like:
#   Gateway event loop: degraded reasons=event_loop_delay max=15066ms p99=27ms util=0.758 cpu=0.009
# We parse the status word and max latency from this line.
container_health=$(docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw health 2>&1 | head -10) || true

# Extract event loop status line
event_loop_line=$(echo "$container_health" | grep -i "event loop" | head -1 || echo "")
if [ -n "$event_loop_line" ]; then
    event_loop_status=$(echo "$event_loop_line" | awk '{print $4}')  # e.g., "degraded"
    event_loop_max=$(echo "$event_loop_line" | grep -oE 'max=[0-9]+ms' | head -1 || echo "unknown")
    event_loop="${event_loop_status} ${event_loop_max}"
else
    event_loop="unknown"
fi

# Only flag as issue if gateway health shows error or critical (not degraded —
# degraded event loop is common and gateway-wide, not Relay-specific)
if echo "$container_health" | grep -qi "error\|critical"; then
    problem_line=$(echo "$container_health" | grep -iE 'error|critical' | head -1 | tr '"' "'" | cut -c1-120)
    issues+=("{\"component\":\"gateway\",\"problem\":\"$problem_line\",\"fix_action\":\"gateway-restart\"}")
fi

# ---------- 2. Stability State ----------
# stability-monitor.sh writes this file. Missing file = assume stable.
stability="stable"
if [ -f /root/.openclaw/stability-state.json ]; then
    stability=$(python3 -c "
import json, sys
try:
    d = json.load(open('/root/.openclaw/stability-state.json'))
    print(d.get('state', 'unknown'))
except Exception:
    print('unknown')
" 2>/dev/null)
    if [ "$stability" = "quarantined" ] || [ "$stability" = "degraded" ]; then
        issues+=("{\"component\":\"stability\",\"problem\":\"System state: $stability\",\"fix_action\":\"gateway-restart\"}")
    fi
fi

# ---------- 3. Disk Usage ----------
# Alert at 85%. Docker images, build cache, and logs are the usual culprits.
# Fix: `docker system prune` or check /var/log sizes.
disk_line=$(df -h / | tail -1)
disk_used=$(echo "$disk_line" | awk '{print $5}' | tr -d '%')
disk_human=$(echo "$disk_line" | awk '{printf "%s/%s (%s)", $3, $2, $5}')
if [ "$disk_used" -gt 85 ]; then
    issues+=("{\"component\":\"disk\",\"problem\":\"Disk at ${disk_used}% — check docker images and logs\",\"fix_action\":\"infra-audit\"}")
fi

# ---------- 4. Memory Usage ----------
# Alert at 85%. The gateway container and host-ops-executor share 8GB.
# If memory is high, check for runaway processes or too many concurrent agents.
mem_line=$(free -h | grep Mem)
mem_used=$(free | grep Mem | awk '{printf "%.0f", $3/$2*100}')
mem_human=$(echo "$mem_line" | awk '{printf "%s/%s (%s%%)", $3, $2, '"$mem_used"'}')
if [ "$mem_used" -gt 85 ]; then
    issues+=("{\"component\":\"memory\",\"problem\":\"Memory at ${mem_used}% — check concurrent agents\",\"fix_action\":\"infra-audit\"}")
fi

# ---------- 5. Systemd Services ----------
# Two critical services:
#   openclaw-host-ops: polls ops.db, executes host-side tasks (reactor, health, etc.)
#   openclaw-bridge-dev: serves the Bridge web UI on port 8082
# If either is down, Relay loses capabilities.
services_ok=true
for svc in openclaw-host-ops openclaw-bridge-dev; do
    svc_status=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    if [ "$svc_status" != "active" ]; then
        services_ok=false
        issues+=("{\"component\":\"$svc\",\"problem\":\"Service $svc_status — Relay cannot dispatch host-side work without this\",\"fix_action\":\"systemctl restart $svc\"}")
    fi
done

# ---------- 6. Recent Task Health ----------
# Query ops.db for task distribution in last 24h.
# >3 blocked tasks signals a stuck pipeline (bad handler, missing script, etc.)
task_summary=""
if [ -f /root/.openclaw/ops.db ]; then
    task_summary=$(sqlite3 /root/.openclaw/ops.db \
        "SELECT status, COUNT(*) FROM tasks WHERE created_at > datetime('now', '-24 hours') GROUP BY status" \
        2>/dev/null | tr '\n' ', ' | sed 's/,$//' || echo "db_error")
    blocked_count=$(sqlite3 /root/.openclaw/ops.db \
        "SELECT COUNT(*) FROM tasks WHERE status='blocked' AND created_at > datetime('now', '-24 hours')" \
        2>/dev/null || echo "0")
    if [ "$blocked_count" -gt 3 ]; then
        issues+=("{\"component\":\"tasks\",\"problem\":\"$blocked_count blocked tasks in 24h — pipeline may be stuck\",\"fix_action\":\"error-audit\"}")
    fi
fi

# ---------- 7. Build JSON Output ----------
if [ ${#issues[@]} -eq 0 ]; then
    overall="healthy"
else
    overall="issues_found"
fi

# Build issues array manually (no jq dependency)
issues_json="["
for i in "${!issues[@]}"; do
    if [ "$i" -gt 0 ]; then issues_json+=","; fi
    issues_json+="${issues[$i]}"
done
issues_json+="]"

cat <<EOF
{
  "overall_status": "$overall",
  "event_loop": "$event_loop",
  "stability": "$stability",
  "disk": "$disk_human",
  "memory": "$mem_human",
  "services_ok": $services_ok,
  "tasks_24h": "$task_summary",
  "issues": $issues_json,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
