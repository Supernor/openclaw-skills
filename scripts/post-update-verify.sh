#!/usr/bin/env bash
# post-update-verify.sh — Golden script for post-update verification
#
# PURPOSE: Verify system health after an OpenClaw update. Combines native
# doctor/validate with custom model and process checks. Returns JSON summary.
# Runs on HOST via host-ops-executor.
#
# USAGE:
#   bash /root/.openclaw/scripts/post-update-verify.sh
#   # Returns JSON to stdout. Always exits 0 (issues reported in output).
#
# CHECKS:
#   1. openclaw doctor --fix --yes (native migrations + plugin reinstall)
#   2. openclaw config validate (native config validation)
#   3. Plugin check (codex enabled and loaded)
#   4. Auth health (profile status via native health)
#   5. Process checks (host-ops, bridge-dev, telegram-listener)
#   6. Container health (Docker healthcheck status)
#
# HISTORY:
#   Created 2026-05-20 during Phase 0.5 (Harden + Doctor).
#   Prevents the class of failure where codex plugin vanishes silently.

set -uo pipefail

AUTO_FIX=false
[ "${1:-}" = "--auto-fix" ] && AUTO_FIX=true

DC="docker compose -f /root/openclaw/docker-compose.yml"
issues=()
auto_fixed=()
checks_passed=0
checks_total=0

try_fix() {
    local check_name="$1" action="$2"
    $AUTO_FIX || return 1
    case "$check_name" in
        codex_plugin)   timeout 15 $DC exec -T openclaw-gateway node dist/index.js doctor --fix --yes >/dev/null 2>&1 ;;
        openclaw-host-ops)   systemctl restart openclaw-host-ops 2>&1 ;;
        openclaw-bridge-dev) systemctl restart openclaw-bridge-dev 2>&1 ;;
        container_health)    /root/.openclaw/scripts/gateway-restart-safe.sh 8561305605 "auto-fix: container_health" --force 2>&1 ;;
        auth_health)         /root/.openclaw/scripts/codex-reauth-telegram.sh 8561305605 2>&1 ;;
        *)                   return 1 ;;  # doctor, config_validate — skip
    esac
    local rc=$?
    if [ $rc -eq 0 ]; then
        auto_fixed+=("{\"check\":\"$check_name\",\"action\":\"$action\",\"success\":true}")
    else
        auto_fixed+=("{\"check\":\"$check_name\",\"action\":\"$action\",\"success\":false}")
    fi
    return $rc
}

check() {
    local name="$1" status="$2" detail="$3" fix_action="${4:-}"
    checks_total=$((checks_total + 1))
    if [ "$status" = "pass" ]; then
        checks_passed=$((checks_passed + 1))
    else
        local entry="{\"check\":\"$name\",\"status\":\"$status\",\"detail\":\"$detail\""
        if [ -n "$fix_action" ]; then
            entry="$entry,\"fix_action\":\"$fix_action\""
        fi
        entry="$entry}"
        issues+=("$entry")
    fi
}

# ---------- 1. Doctor (native migrations + plugin health) ----------
doctor_out=$(timeout 15 $DC exec -T openclaw-gateway node dist/index.js doctor --fix --yes 2>&1 | tail -20) || true
if echo "$doctor_out" | grep -qi "Doctor complete"; then
    check "doctor" "pass" "ok"
else
    detail=$(echo "$doctor_out" | grep -iE "error|fail" | head -1 | tr '"' "'" | cut -c1-100)
    check "doctor" "fail" "${detail:-doctor did not complete}" "gateway-restart"
fi

# ---------- 2. Config Validate ----------
config_out=$(timeout 15 $DC exec -T openclaw-gateway node dist/index.js config validate 2>&1) || true
if echo "$config_out" | grep -qi "Config valid"; then
    check "config_validate" "pass" "ok"
else
    detail=$(echo "$config_out" | grep -iE "error\|invalid\|fail" | head -1 | tr '"' "'" | cut -c1-100)
    check "config_validate" "fail" "${detail:-config validation failed}"
fi

# ---------- 3. Codex Plugin Check ----------
plugin_out=$(timeout 15 $DC exec -T openclaw-gateway node dist/index.js plugins list 2>&1) || true
if echo "$plugin_out" | grep -q "codex.*enabled"; then
    codex_ver=$(echo "$plugin_out" | grep "codex" | grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+' | head -1)
    check "codex_plugin" "pass" "v${codex_ver:-unknown}"
else
    check "codex_plugin" "fail" "codex plugin not enabled — agents will fall to Mistral" "codex-reauth"
fi

# ---------- 4. Auth Health ----------
health_out=$(timeout 15 $DC exec -T openclaw-gateway node dist/index.js health 2>&1) || true
if echo "$health_out" | grep -qi "expired\|missing"; then
    detail=$(echo "$health_out" | grep -iE "expired|missing" | head -1 | tr '"' "'" | cut -c1-100)
    check "auth_health" "warn" "$detail" "codex-reauth"
elif echo "$health_out" | grep -qi "expiring"; then
    detail=$(echo "$health_out" | grep -i "expiring" | head -1 | tr '"' "'" | cut -c1-100)
    check "auth_health" "warn" "$detail"
else
    check "auth_health" "pass" "ok"
fi

# ---------- 5. Host Process Checks ----------
for svc in openclaw-host-ops openclaw-bridge-dev; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        check "$svc" "pass" "active"
    else
        check "$svc" "fail" "service not running" "gateway-restart"
    fi
done

# Telegram listener
if pgrep -f "telegram-listener" > /dev/null 2>&1; then
    check "telegram_listener" "pass" "running"
else
    check "telegram_listener" "warn" "not running"
fi

# ---------- 6. Container Health ----------
container_status=$(docker inspect --format='{{.State.Health.Status}}' "$(docker compose -f /root/openclaw/docker-compose.yml ps -q openclaw-gateway 2>/dev/null)" 2>/dev/null) || container_status="unknown"
if [ "$container_status" = "healthy" ]; then
    check "container_health" "pass" "healthy"
else
    check "container_health" "warn" "$container_status"
fi

# ---------- Build JSON output ----------
issue_json="[]"
if [ ${#issues[@]} -gt 0 ]; then
    issue_json=$(printf '%s\n' "${issues[@]}" | paste -sd ',' | sed 's/^/[/;s/$/]/')
fi

overall="pass"
for iss in "${issues[@]+"${issues[@]}"}"; do
    if echo "$iss" | grep -q '"fail"'; then
        overall="fail"
        break
    fi
    if echo "$iss" | grep -q '"warn"'; then
        overall="warn"
    fi
done

# If auto-fix is on, attempt fixes for failing checks then re-verify
if $AUTO_FIX && [ ${#issues[@]} -gt 0 ]; then
    for iss in "${issues[@]}"; do
        chk=$(echo "$iss" | grep -oP '"check":"\K[^"]+' || echo "")
        [ -n "$chk" ] && try_fix "$chk" "auto-fix-$chk" && {
            # E7: Re-verify after fix — confirm the fix actually worked
            reverify="unknown"
            case "$chk" in
                codex_plugin)
                    timeout 15 $DC exec -T openclaw-gateway node dist/index.js plugins list 2>&1 | grep -q "codex.*enabled" && reverify="pass" || reverify="still_failing" ;;
                openclaw-host-ops|openclaw-bridge-dev)
                    sleep 2 && systemctl is-active --quiet "$chk" 2>/dev/null && reverify="pass" || reverify="still_failing" ;;
                container_health)
                    sleep 5 && cs=$(docker inspect --format='{{.State.Health.Status}}' "$(docker compose -f /root/openclaw/docker-compose.yml ps -q openclaw-gateway 2>/dev/null)" 2>/dev/null)
                    [ "$cs" = "healthy" ] && reverify="pass" || reverify="still_failing" ;;
                auth_health)
                    sleep 3 && timeout 15 $DC exec -T openclaw-gateway node dist/index.js health 2>&1 | grep -qi "expired\|missing" && reverify="still_failing" || reverify="pass" ;;
            esac
            # Update the auto_fixed entry with re-verification result
            auto_fixed[-1]=$(echo "${auto_fixed[-1]}" | sed "s/}$/,\"reverify\":\"$reverify\"}/")
        } || true
    done
fi

fixed_json="[]"
if [ ${#auto_fixed[@]} -gt 0 ]; then
    fixed_json=$(printf '%s\n' "${auto_fixed[@]}" | paste -sd ',' | sed 's/^/[/;s/$/]/')
fi

cat <<EOF
{"overall":"$overall","passed":$checks_passed,"total":$checks_total,"issues":$issue_json,"auto_fixed":$fixed_json,"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
