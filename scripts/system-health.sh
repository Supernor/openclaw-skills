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

AUTO_FIX=false
[ "${1:-}" = "--auto-fix" ] && AUTO_FIX=true

issues=()
auto_fixed=()

try_fix() {
    local component="$1" action="$2"
    $AUTO_FIX || return 1
    # Allowlist: only safe, idempotent repairs
    case "$action" in
        gateway-restart)
            /root/.openclaw/scripts/gateway-restart-safe.sh 8561305605 "auto-fix: $component" --force 2>&1 && { auto_fixed+=("{\"component\":\"$component\",\"action\":\"$action\",\"success\":true}"); return 0; } || { auto_fixed+=("{\"component\":\"$component\",\"action\":\"$action\",\"success\":false}"); return 1; }
            ;;
        "systemctl restart"*)
            $action 2>&1 && { auto_fixed+=("{\"component\":\"$component\",\"action\":\"$action\",\"success\":true}"); return 0; } || { auto_fixed+=("{\"component\":\"$component\",\"action\":\"$action\",\"success\":false}"); return 1; }
            ;;
        codex-reauth)
            /root/.openclaw/scripts/codex-reauth-telegram.sh 8561305605 2>&1 && { auto_fixed+=("{\"component\":\"$component\",\"action\":\"$action\",\"success\":true}"); return 0; } || { auto_fixed+=("{\"component\":\"$component\",\"action\":\"$action\",\"success\":false}"); return 1; }
            ;;
        *)
            return 1  # deny list: infra-audit, error-audit, reactor-dispatch, etc.
            ;;
    esac
}

# ---------- 1. Container / Gateway Health ----------
# `openclaw health` outputs lines like:
#   Gateway event loop: degraded reasons=event_loop_delay max=15066ms p99=27ms util=0.758 cpu=0.009
# We parse the status word and max latency from this line.
container_health=$(timeout 15 docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw health 2>&1 | head -10) || true

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

# ---------- 2b. Auth Health ----------
# Parse JWT expiry from Codex auth-profiles. Would have caught the 12-day degradation.
# Alert if any pool expires in <12 hours.
auth_status="ok"
auth_detail=""
auth_check=$(python3 -c "
import json, base64, time
try:
    with open('/home/node/.openclaw/agents/main/agent/auth-profiles.json') as f:
        d = json.load(f)
    profiles = d.get('profiles', {})
    min_hours = 999
    expiring = []
    for pid, p in profiles.items():
        token = p.get('access', '')
        if not token or '.' not in token:
            continue
        payload = token.split('.')[1] + '==='
        claims = json.loads(base64.urlsafe_b64decode(payload))
        remaining_h = (claims.get('exp', 0) - time.time()) / 3600
        if remaining_h < min_hours:
            min_hours = remaining_h
        if remaining_h < 12:
            expiring.append(f'{pid}: {remaining_h:.1f}h left')
    if expiring:
        print('EXPIRING|' + '; '.join(expiring))
    elif min_hours < 24:
        print(f'LOW|Lowest: {min_hours:.1f}h remaining')
    else:
        print(f'OK|{min_hours:.0f}h remaining')
except Exception as e:
    print(f'ERROR|{e}')
" 2>/dev/null)

auth_level=$(echo "$auth_check" | cut -d'|' -f1)
auth_detail=$(echo "$auth_check" | cut -d'|' -f2-)

if [ "$auth_level" = "EXPIRING" ]; then
    issues+=("{\"component\":\"auth\",\"problem\":\"Codex auth expiring: $auth_detail\",\"fix_action\":\"codex-reauth\"}")
elif [ "$auth_level" = "ERROR" ]; then
    issues+=("{\"component\":\"auth\",\"problem\":\"Auth check failed: $auth_detail\",\"fix_action\":\"codex-reauth\"}")
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
        "SELECT status, COUNT(*) FROM tasks WHERE created_at > strftime('%Y-%m-%dT%H:%M:%SZ','now', '-24 hours') GROUP BY status" \
        2>/dev/null | tr '\n' ', ' | sed 's/,$//' || echo "db_error")
    blocked_count=$(sqlite3 /root/.openclaw/ops.db \
        "SELECT COUNT(*) FROM tasks WHERE status='blocked' AND created_at > strftime('%Y-%m-%dT%H:%M:%SZ','now', '-24 hours')" \
        2>/dev/null || echo "0")
    if [ "$blocked_count" -gt 3 ]; then
        issues+=("{\"component\":\"tasks\",\"problem\":\"$blocked_count blocked tasks in 24h — pipeline may be stuck\",\"fix_action\":\"error-audit\"}")
    fi
fi

# ---------- 7. Engine Blackout Detection ----------
# If BOTH Codex pools AND Gemini have >70% failure rate in last hour, nobody can do work.
# State-change driven: only alert on transition INTO blackout, not every check.
if [ -f /root/.openclaw/ops.db ]; then
    blackout_check=$(sqlite3 /root/.openclaw/ops.db "
        SELECT
            COALESCE((SELECT CASE WHEN COUNT(*) >= 3 AND (SUM(success)*1.0/COUNT(*)) < 0.3 THEN 1 ELSE 0 END
                FROM engine_usage WHERE engine='codex' AND pool='pool-a' AND ts > strftime('%Y-%m-%dT%H:%M:%SZ','now', '-60 minutes')), 0) AS codex_a_dead,
            COALESCE((SELECT CASE WHEN COUNT(*) >= 3 AND (SUM(success)*1.0/COUNT(*)) < 0.3 THEN 1 ELSE 0 END
                FROM engine_usage WHERE engine='codex' AND pool='pool-b' AND ts > strftime('%Y-%m-%dT%H:%M:%SZ','now', '-60 minutes')), 0) AS codex_b_dead,
            COALESCE((SELECT CASE WHEN COUNT(*) >= 3 AND (SUM(success)*1.0/COUNT(*)) < 0.3 THEN 1 ELSE 0 END
                FROM engine_usage WHERE engine='gemini' AND ts > strftime('%Y-%m-%dT%H:%M:%SZ','now', '-60 minutes')), 0) AS gemini_dead
    " 2>/dev/null || echo "0|0|0")

    codex_a_dead=$(echo "$blackout_check" | cut -d'|' -f1)
    codex_b_dead=$(echo "$blackout_check" | cut -d'|' -f2)
    gemini_dead=$(echo "$blackout_check" | cut -d'|' -f3)

    if [ "$codex_a_dead" = "1" ] && [ "$codex_b_dead" = "1" ] && [ "$gemini_dead" = "1" ]; then
        issues+=("{\"component\":\"engines\",\"problem\":\"TOTAL ENGINE BLACKOUT — all engines failing >70% in last hour\",\"fix_action\":\"infra-audit\"}")

        # State-change: only alert once per blackout episode
        prev_blackout=$(sqlite3 /root/.openclaw/ops.db "SELECT value FROM kv WHERE key='engine_blackout_active'" 2>/dev/null || echo "")
        if [ "$prev_blackout" != "1" ]; then
            sqlite3 /root/.openclaw/ops.db "INSERT OR REPLACE INTO kv (key, value) VALUES ('engine_blackout_active', '1')" 2>/dev/null
            # Direct Telegram alert — bypasses gateway (which may also be affected)
            TOKEN=$(grep '^TELEGRAM_BOT_TOKEN_ROBERT=' /root/openclaw/.env 2>/dev/null | cut -d= -f2)
            [ -n "$TOKEN" ] && curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
                -d chat_id="8561305605" \
                -d text="*ENGINE BLACKOUT* -- All engines failing (Codex pool-a, pool-b, Gemini). No AI work can proceed. Check API keys, rate limits, and network." \
                -d parse_mode=Markdown >/dev/null 2>&1
        fi
    else
        # Clear blackout flag if recovered
        sqlite3 /root/.openclaw/ops.db "DELETE FROM kv WHERE key='engine_blackout_active'" 2>/dev/null || true
    fi
fi

# ---------- 8. Build JSON Output ----------
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

# If auto-fix is on, attempt fixes for each issue then re-verify
if $AUTO_FIX && [ ${#issues[@]} -gt 0 ]; then
    for iss in "${issues[@]}"; do
        comp=$(echo "$iss" | grep -oP '"component":"\K[^"]+' || echo "")
        act=$(echo "$iss" | grep -oP '"fix_action":"\K[^"]+' || echo "")
        [ -n "$act" ] && try_fix "$comp" "$act" && {
            # E7: Re-verify after fix
            reverify="unknown"
            case "$comp" in
                gateway)
                    sleep 5 && timeout 15 docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw health 2>&1 | grep -qi "error\|critical" && reverify="still_failing" || reverify="pass" ;;
                openclaw-host-ops|openclaw-bridge-dev)
                    sleep 2 && systemctl is-active --quiet "$comp" 2>/dev/null && reverify="pass" || reverify="still_failing" ;;
                stability)
                    sleep 5 && timeout 15 docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw health 2>&1 | grep -qi "error\|critical" && reverify="still_failing" || reverify="pass" ;;
                *) reverify="not_checked" ;;
            esac
            auto_fixed[-1]=$(echo "${auto_fixed[-1]}" | sed "s/}$/,\"reverify\":\"$reverify\"}/")
        } || true
    done
fi

# Build auto_fixed JSON
fixed_json="[]"
if [ ${#auto_fixed[@]} -gt 0 ]; then
    fixed_json="["
    for i in "${!auto_fixed[@]}"; do
        [ "$i" -gt 0 ] && fixed_json+=","
        fixed_json+="${auto_fixed[$i]}"
    done
    fixed_json+="]"
fi

cat <<EOF
{
  "overall_status": "$overall",
  "event_loop": "$event_loop",
  "stability": "$stability",
  "auth": "$auth_detail",
  "disk": "$disk_human",
  "memory": "$mem_human",
  "services_ok": $services_ok,
  "tasks_24h": "$task_summary",
  "issues": $issues_json,
  "auto_fixed": $fixed_json,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
