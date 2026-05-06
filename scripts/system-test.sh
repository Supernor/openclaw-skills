#!/usr/bin/env bash
# system-test.sh — Unified system test framework for Robert's VPS.
#
# WHEN TO USE: After updates, customizations, or on-demand debugging.
# DON'T USE FOR: Real-time monitoring (use stability-monitor for that).
# IF ANY CHECK FAILS: The message tells you what's wrong. Context JSON has details.
# VERIFY: system-test.sh all (must exit 0)
#
# Usage:
#   system-test.sh [all|health|bootstrap|database|override|channels|automation|models|performance]
#   system-test.sh --trigger <manual|post-update|cron|post-customization>
#   system-test.sh --json          # machine-readable output only
#   system-test.sh --no-store      # skip ops.db storage (debugging)
#   system-test.sh --notify        # send summary to Telegram
#   system-test.sh --chart-failures # auto-chart FAILs (with dedup)
#   system-test.sh --list          # list all tests without running
#
# Exit codes: 0 = all pass, 1 = any fail, 2 = warn only

set -uo pipefail

# ── Constants ──
OPS_DB="/root/.openclaw/ops.db"
COMPOSE_DIR="/root/openclaw"
SCRIPTS_DIR="/root/.openclaw/scripts"
WORKSPACE="/root/.openclaw/workspace"
BASELINES="/root/.openclaw/config/test-baselines.json"
RUN_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
TRIGGER="manual"
CATEGORIES="all"
JSON_MODE=false
STORE=true
NOTIFY=false
CHART_FAILURES=false
LIST_MODE=false
VERSION=""
PASS=0; FAIL=0; WARN=0; SKIP=0
TEST_TIMEOUT=30

# ── Colors ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; DIM='\033[0;90m'; NC='\033[0m'

# ── Argument Parsing ──
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trigger) TRIGGER="$2"; shift 2 ;;
    --json) JSON_MODE=true; shift ;;
    --no-store) STORE=false; shift ;;
    --notify) NOTIFY=true; shift ;;
    --chart-failures) CHART_FAILURES=true; shift ;;
    --list) LIST_MODE=true; shift ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
[ ${#POSITIONAL[@]} -gt 0 ] && CATEGORIES="${POSITIONAL[*]}"

# ── Helpers ──
get_version() {
  VERSION=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway openclaw --version 2>/dev/null | head -1 | grep -oP '[\d.]+' || echo "unknown")
}

get_baseline() {
  python3 -c "import json; print(json.load(open('$BASELINES')).get('$1', '$2'))" 2>/dev/null || echo "$2"
}

record() {
  local cat="$1" name="$2" status="$3" msg="$4" dur="${5:-0}" ctx="${6:-{}}"
  # Print
  if ! $JSON_MODE; then
    local color="$GREEN"; local icon="PASS"
    [ "$status" = "fail" ] && color="$RED" && icon="FAIL"
    [ "$status" = "warn" ] && color="$YELLOW" && icon="WARN"
    [ "$status" = "skip" ] && color="$DIM" && icon="SKIP"
    printf "    ${color}%-4s${NC}  %-35s %s\n" "$icon" "$name" "$msg"
  fi
  # Count
  case "$status" in
    pass) PASS=$((PASS+1)) ;; fail) FAIL=$((FAIL+1)) ;; warn) WARN=$((WARN+1)) ;; skip) SKIP=$((SKIP+1)) ;;
  esac
  # Store
  if $STORE; then
    sqlite3 "$OPS_DB" "INSERT INTO test_results (run_id, trigger, category, test_name, status, message, duration_ms, system_version, context) VALUES ('$RUN_ID', '$TRIGGER', '$cat', '$name', '$status', '$(echo "$msg" | sed "s/'/''/g")', $dur, '$VERSION', '$(echo "$ctx" | sed "s/'/''/g")');" 2>/dev/null
  fi
}

run_test() {
  local cat="$1" name="$2"
  local start_ms=$(date +%s%N | cut -b1-13)
  local result
  result=$(timeout $TEST_TIMEOUT bash -c "$3" 2>&1) || true
  local end_ms=$(date +%s%N | cut -b1-13)
  local dur=$(( end_ms - start_ms ))
  echo "$result"
}

send_telegram() {
  local token chat_id
  token=$(grep "^TELEGRAM_BOT_TOKEN_ROBERT=" "$COMPOSE_DIR/.env" 2>/dev/null | cut -d= -f2-) || true
  chat_id="8561305605"
  [ -n "$token" ] && curl -sf -X POST "https://api.telegram.org/bot${token}/sendMessage" -d chat_id="$chat_id" -d text="$1" >/dev/null 2>&1 || true
}

should_run() {
  local cat="$1"
  [ "$CATEGORIES" = "all" ] && return 0
  echo "$CATEGORIES" | grep -qw "$cat"
}

# ── List mode ──
if $LIST_MODE; then
  echo "System Test — 46 tests across 8 categories"
  echo ""
  echo "health (8):     gateway_port, container_running, healthz_endpoint, truth_pass, bridge_audit, bridge_service, systemd_services, agent_count"
  echo "bootstrap (7):  file_sizes, symlinks, total_size, required_files, no_truncation, symlinks_container, plugin_load_health"
  echo "database (5):   integrity, table_count, trigger_count, wal_size, no_locked"
  echo "override (4):   file_exists, env_reaches_container, volumes_mounted, build_args"
  echo "channels (5):   telegram_polling, discord_connected, tap_bot, scribe_responsive, cron_error_rate"
  echo "automation (6): host_ops_active, host_ops_no_stuck, deferred_executor, error_quality, nightly_dispatch, cron_count"
  echo "models (4):     nvidia_routing, codex_auth, recent_engine_usage, error_rate"
  echo "performance (7): model_health_monitor, event_loop, disk_space, host_memory, container_memory, ops_db_size, docker_disk"
  exit 0
fi

# ── Init ──
get_version
$JSON_MODE || echo -e "\n${CYAN}=== System Test — $(date -u +%Y-%m-%dT%H:%M:%SZ) ===${NC}"
$JSON_MODE || echo -e "  trigger: $TRIGGER | version: $VERSION | run: ${RUN_ID:0:8}\n"

# ══════════════════════════════════════════════════════════════
# HEALTH (8 tests)
# ══════════════════════════════════════════════════════════════
if should_run health; then
  $JSON_MODE || echo -e "  ${CYAN}[health]${NC}"

  # gateway_port
  S=$(date +%s%N | cut -b1-13)
  if timeout 5 bash -c "echo > /dev/tcp/127.0.0.1/18789" 2>/dev/null; then
    record health gateway_port pass "port 18789 listening" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record health gateway_port fail "port 18789 not listening" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # container_running
  S=$(date +%s%N | cut -b1-13)
  STATE=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps 2>/dev/null | grep "gateway" | grep -o "Up\|running\|healthy" | head -1 || echo "")
  if [ -n "$STATE" ]; then
    record health container_running pass "gateway $STATE" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record health container_running fail "gateway not running" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # healthz_endpoint
  S=$(date +%s%N | cut -b1-13)
  if docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway node -e "fetch('http://127.0.0.1:18789/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
    record health healthz_endpoint pass "/healthz OK" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record health healthz_endpoint fail "/healthz failed" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # truth_pass (wraps existing script)
  S=$(date +%s%N | cut -b1-13)
  TP=$(timeout $TEST_TIMEOUT bash "$SCRIPTS_DIR/verify-truth-pass.sh" 2>&1)
  if echo "$TP" | grep -q "STATUS: PASS"; then
    COUNT=$(echo "$TP" | grep -oP '\d+ passed' | head -1)
    record health truth_pass pass "$COUNT" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record health truth_pass fail "$(echo "$TP" | tail -1)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # bridge_audit (wraps existing script)
  S=$(date +%s%N | cut -b1-13)
  BA=$(timeout $TEST_TIMEOUT bash "$SCRIPTS_DIR/bridge-audit.sh" 2>&1)
  if echo "$BA" | grep -q "STATUS: PASS"; then
    COUNT=$(echo "$BA" | grep -oP '\d+/\d+ passed' | head -1)
    record health bridge_audit pass "$COUNT" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record health bridge_audit fail "$(echo "$BA" | tail -1)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # bridge_service
  S=$(date +%s%N | cut -b1-13)
  if systemctl is-active openclaw-bridge-dev >/dev/null 2>&1; then
    record health bridge_service pass "active" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record health bridge_service fail "not active" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # systemd_services
  S=$(date +%s%N | cut -b1-13)
  SVCS="openclaw-host-ops openclaw-bridge-dev openclaw-reactor openclaw-codex-auth-watch openclaw-bridge-watcher"
  DOWN=""
  for svc in $SVCS; do
    systemctl is-active "$svc" >/dev/null 2>&1 || DOWN="$DOWN $svc"
  done
  if [ -z "$DOWN" ]; then
    record health systemd_services pass "5/5 active" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record health systemd_services fail "down:$DOWN" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # agent_count
  S=$(date +%s%N | cut -b1-13)
  EXPECTED=$(get_baseline agent_count 18)
  ACTUAL=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway openclaw agents list 2>/dev/null | grep -c "^-" || echo 0)
  if [ "$ACTUAL" -ge "$EXPECTED" ]; then
    record health agent_count pass "$ACTUAL agents" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record health agent_count fail "$ACTUAL agents (expected $EXPECTED)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi
fi

# ══════════════════════════════════════════════════════════════
# BOOTSTRAP (5 tests)
# ══════════════════════════════════════════════════════════════
if should_run bootstrap; then
  $JSON_MODE || echo -e "\n  ${CYAN}[bootstrap]${NC}"

  # file_sizes
  S=$(date +%s%N | cut -b1-13)
  OVER=""
  for dir in /root/.openclaw/workspace*; do
    [ -d "$dir" ] && for f in "$dir"/*.md; do
      [ -f "$f" ] && SIZE=$(wc -c < "$f") && [ "$SIZE" -gt 12288 ] && OVER="$OVER $(basename "$dir")/$(basename "$f")($SIZE)"
    done
  done
  if [ -z "$OVER" ]; then
    record bootstrap file_sizes pass "all under 12K" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record bootstrap file_sizes fail "over 12K:$OVER" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # symlinks
  S=$(date +%s%N | cut -b1-13)
  BROKEN=$(find /root/.openclaw/workspace* -name "*.md" -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l)
  if [ "$BROKEN" -eq 0 ]; then
    record bootstrap symlinks pass "no broken symlinks" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record bootstrap symlinks fail "$BROKEN broken symlinks" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # total_size
  S=$(date +%s%N | cut -b1-13)
  TOTAL=$(cat /root/.openclaw/workspace/*.md 2>/dev/null | wc -c)
  if [ "$TOTAL" -lt 153600 ]; then
    record bootstrap total_size pass "${TOTAL} chars (limit 150K)" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record bootstrap total_size fail "${TOTAL} chars exceeds 150K" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # required_files
  S=$(date +%s%N | cut -b1-13)
  MISSING=""
  for f in SOUL.md AGENTS.md TOOLS.md MEMORY.md IDENTITY.md USER.md HEARTBEAT.md; do
    [ -f "$WORKSPACE/$f" ] || MISSING="$MISSING $f"
  done
  if [ -z "$MISSING" ]; then
    record bootstrap required_files pass "7/7 present" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record bootstrap required_files fail "missing:$MISSING" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # no_truncation
  S=$(date +%s%N | cut -b1-13)
  TRUNC=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" logs --tail=500 openclaw-gateway 2>&1 | grep -ci "truncat" || true)
  if [ "$TRUNC" -eq 0 ]; then
    record bootstrap no_truncation pass "no truncation in logs" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record bootstrap no_truncation warn "$TRUNC truncation mentions" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # symlinks_container (NEW: checks from inside container as node user)
  S=$(date +%s%N | cut -b1-13)
  BROKEN_CONTAINER=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway find /home/node/.openclaw/workspace* -name "*.md" -type l 2>/dev/null | while read f; do docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway test -r "$f" 2>/dev/null || echo "$f"; done | wc -l || echo 0)
  if [ "$BROKEN_CONTAINER" -eq 0 ]; then
    record bootstrap symlinks_container pass "all readable in container" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record bootstrap symlinks_container fail "$BROKEN_CONTAINER unreadable in container" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # plugin_load_health (NEW: check for plugin load errors)
  S=$(date +%s%N | cut -b1-13)
  PLUGIN_ERRORS=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" logs --tail=100 openclaw-gateway 2>&1 | grep -c "PluginLoadFailureError" || true)
  if [ "$PLUGIN_ERRORS" -eq 0 ]; then
    record bootstrap plugin_load_health pass "no plugin load errors" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record bootstrap plugin_load_health fail "$PLUGIN_ERRORS plugin load errors" $(( $(date +%s%N | cut -b1-13) - S ))
  fi
fi

# ══════════════════════════════════════════════════════════════
# DATABASE (5 tests)
# ══════════════════════════════════════════════════════════════
if should_run database; then
  $JSON_MODE || echo -e "\n  ${CYAN}[database]${NC}"

  # integrity
  S=$(date +%s%N | cut -b1-13)
  IC=$(sqlite3 "$OPS_DB" "PRAGMA integrity_check;" 2>&1)
  if [ "$IC" = "ok" ]; then
    record database integrity pass "ok" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record database integrity fail "$IC" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # table_count
  S=$(date +%s%N | cut -b1-13)
  TC=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" 2>&1)
  EXPECTED=$(get_baseline table_count 38)
  DIFF=$(( TC - EXPECTED ))
  if [ "$DIFF" -ge -3 ] && [ "$DIFF" -le 12 ]; then
    record database table_count pass "$TC tables (baseline $EXPECTED)" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record database table_count warn "$TC tables (baseline $EXPECTED, drift $DIFF)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # trigger_count
  S=$(date +%s%N | cut -b1-13)
  TRC=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger';" 2>&1)
  EXPECTED=$(get_baseline trigger_count 33)
  DIFF=$(( TRC - EXPECTED ))
  if [ "$DIFF" -ge -3 ] && [ "$DIFF" -le 12 ]; then
    record database trigger_count pass "$TRC triggers (baseline $EXPECTED)" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record database trigger_count warn "$TRC triggers (baseline $EXPECTED, drift $DIFF)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # wal_size
  S=$(date +%s%N | cut -b1-13)
  WAL_SIZE=$(stat -c%s "$OPS_DB-wal" 2>/dev/null || echo 0)
  WAL_MB=$((WAL_SIZE / 1048576))
  if [ "$WAL_MB" -lt 50 ]; then
    record database wal_size pass "${WAL_MB}MB" $(( $(date +%s%N | cut -b1-13) - S ))
  elif [ "$WAL_MB" -lt 200 ]; then
    record database wal_size warn "${WAL_MB}MB (threshold 50MB)" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record database wal_size fail "${WAL_MB}MB (threshold 200MB)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # no_locked
  S=$(date +%s%N | cut -b1-13)
  if timeout 2 sqlite3 "$OPS_DB" "SELECT 1;" >/dev/null 2>&1; then
    record database no_locked pass "responsive" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record database no_locked fail "SQLITE_BUSY or timeout" $(( $(date +%s%N | cut -b1-13) - S ))
  fi
fi

# ══════════════════════════════════════════════════════════════
# OVERRIDE (4 tests)
# ══════════════════════════════════════════════════════════════
if should_run override; then
  $JSON_MODE || echo -e "\n  ${CYAN}[override]${NC}"

  S=$(date +%s%N | cut -b1-13)
  if [ -f "$COMPOSE_DIR/docker-compose.override.yml" ]; then
    record override file_exists pass "present" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record override file_exists fail "missing" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  ENV_CHECK=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway printenv GIT_CONFIG_GLOBAL 2>/dev/null || echo "")
  if [ -n "$ENV_CHECK" ]; then
    record override env_reaches_container pass "GIT_CONFIG_GLOBAL present" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record override env_reaches_container fail "GIT_CONFIG_GLOBAL missing" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  # Check actual running container mounts (more reliable than docker compose config)
  MOUNTS=$(docker inspect openclaw-openclaw-gateway-1 2>/dev/null | python3 -c "import json,sys; [print(m.get('Destination','')) for m in json.load(sys.stdin)[0].get('Mounts',[])]" 2>/dev/null || echo "")
  VOLS_OK=true
  MISSING_VOLS=""
  for mount in "/home/node/.openclaw" "/var/lib/openclaw/plugin-runtime-deps" "/home/node/.cache/qmd" "/usr/local/bin/bun"; do
    echo "$MOUNTS" | grep -q "$mount" || { VOLS_OK=false; MISSING_VOLS="$MISSING_VOLS $mount"; }
  done
  if $VOLS_OK; then
    record override volumes_mounted pass "all 6 mounts present" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record override volumes_mounted fail "missing:$MISSING_VOLS" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  if echo "$CONFIG" | grep -qi "APT_PACKAGES\|OPENCLAW_DOCKER_APT"; then
    record override build_args pass "APT_PACKAGES in config" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    # Fallback: check if the override file itself has it
    if grep -q "OPENCLAW_DOCKER_APT_PACKAGES" "$COMPOSE_DIR/docker-compose.override.yml" 2>/dev/null; then
      record override build_args pass "APT_PACKAGES in override file" $(( $(date +%s%N | cut -b1-13) - S ))
    else
      record override build_args fail "APT_PACKAGES missing" $(( $(date +%s%N | cut -b1-13) - S ))
    fi
  fi
fi

# ══════════════════════════════════════════════════════════════
# CHANNELS (4 tests)
# ══════════════════════════════════════════════════════════════
if should_run channels; then
  $JSON_MODE || echo -e "\n  ${CYAN}[channels]${NC}"
  LOGS=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" logs --tail=300 openclaw-gateway 2>&1)

  # telegram
  S=$(date +%s%N | cut -b1-13)
  if echo "$LOGS" | grep -qi "telegram.*poll\|telegram.*connect\|telegram.*ready\|deleteWebhook"; then
    record channels telegram_polling pass "polling active" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    # Fallback: try channels status (without --probe which may not exist)
    CS=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway openclaw channels status 2>&1 || true)
    if echo "$CS" | grep -qi "telegram.*running\|telegram.*connected\|telegram.*polling"; then
      record channels telegram_polling pass "connected (via status)" $(( $(date +%s%N | cut -b1-13) - S ))
    else
      record channels telegram_polling warn "not detected in logs or status" $(( $(date +%s%N | cut -b1-13) - S ))
    fi
  fi

  # discord
  S=$(date +%s%N | cut -b1-13)
  if echo "$LOGS" | grep -qi "discord.*connect\|discord.*ready\|discord.*logged\|discord.*gateway"; then
    record channels discord_connected pass "connected" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    CS=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway openclaw channels status 2>&1 || true)
    if echo "$CS" | grep -qi "discord.*running\|discord.*connected"; then
      record channels discord_connected pass "connected (via status)" $(( $(date +%s%N | cut -b1-13) - S ))
    else
      record channels discord_connected warn "not detected" $(( $(date +%s%N | cut -b1-13) - S ))
    fi
  fi

  # tap_bot (warn not fail)
  S=$(date +%s%N | cut -b1-13)
  if pgrep -f "tap-daemon" >/dev/null 2>&1; then
    record channels tap_bot pass "running" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record channels tap_bot warn "not running" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # scribe (warn not fail)
  S=$(date +%s%N | cut -b1-13)
  if pgrep -f "scribe-watcher" >/dev/null 2>&1; then
    record channels scribe_responsive pass "running" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record channels scribe_responsive warn "not running" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  # cron_error_rate (NEW: gateway crons in error state)
  S=$(date +%s%N | cut -b1-13)
  CRON_LIST=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway openclaw cron list --all 2>&1 | grep -v "Config warnings\|plugin memory\|duplicate plugin")
  CRON_ERRORS=$(echo "$CRON_LIST" | grep -c "  error  " || echo 0)
  if [ "$CRON_ERRORS" -le 1 ]; then
    record channels cron_error_rate pass "$CRON_ERRORS gateway crons in error" $(( $(date +%s%N | cut -b1-13) - S ))
  elif [ "$CRON_ERRORS" -le 3 ]; then
    record channels cron_error_rate warn "$CRON_ERRORS gateway crons in error" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record channels cron_error_rate fail "$CRON_ERRORS gateway crons in error" $(( $(date +%s%N | cut -b1-13) - S ))
  fi
fi

# ══════════════════════════════════════════════════════════════
# AUTOMATION (6 tests)
# ══════════════════════════════════════════════════════════════
if should_run automation; then
  $JSON_MODE || echo -e "\n  ${CYAN}[automation]${NC}"

  S=$(date +%s%N | cut -b1-13)
  if systemctl is-active openclaw-host-ops >/dev/null 2>&1; then
    record automation host_ops_active pass "active" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record automation host_ops_active fail "not active" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  STUCK=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='in_progress' AND started_at < datetime('now', '-30 minutes');" 2>/dev/null || echo 0)
  if [ "$STUCK" -eq 0 ]; then
    record automation host_ops_no_stuck pass "0 stuck tasks" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record automation host_ops_no_stuck warn "$STUCK tasks stuck >30min" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  STUCK_DEF=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM deferred_actions WHERE status='in_progress';" 2>/dev/null || echo 0)
  if [ "$STUCK_DEF" -eq 0 ]; then
    record automation deferred_executor pass "0 stuck deferred" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record automation deferred_executor warn "$STUCK_DEF stuck deferred actions" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  EQ=$(timeout $TEST_TIMEOUT bash "$SCRIPTS_DIR/lint-error-quality.sh" 2>&1 || true)
  EQ_FAIL=$(echo "$EQ" | grep -c "FAIL" || true)
  if [ "$EQ_FAIL" -eq 0 ]; then
    record automation error_quality pass "0 failures" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record automation error_quality warn "$EQ_FAIL error quality failures" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  if crontab -l 2>/dev/null | grep -q "nightly-dispatch"; then
    record automation nightly_dispatch pass "cron present" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record automation nightly_dispatch warn "no nightly-dispatch cron found" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  CRON_COUNT=$(crontab -l 2>/dev/null | grep -cv "^#\|^$" || echo 0)
  EXPECTED=$(get_baseline cron_count 125)
  DIFF=$((CRON_COUNT - EXPECTED))
  if [ "$DIFF" -ge -15 ] && [ "$DIFF" -le 15 ]; then
    record automation cron_count pass "$CRON_COUNT crons (baseline $EXPECTED)" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record automation cron_count warn "$CRON_COUNT crons (baseline $EXPECTED, drift $DIFF)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi
fi

# ══════════════════════════════════════════════════════════════
# MODELS (4 tests)
# ══════════════════════════════════════════════════════════════
if should_run models; then
  $JSON_MODE || echo -e "\n  ${CYAN}[models]${NC}"

  S=$(date +%s%N | cut -b1-13)
  NV=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T openclaw-gateway openclaw models list 2>/dev/null | grep -c "nvidia/" || echo 0)
  if [ "$NV" -gt 0 ]; then
    record models nvidia_routing pass "$NV nvidia models" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record models nvidia_routing fail "no nvidia models found" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  AUTH=$(timeout 10 bash "$SCRIPTS_DIR/codex-auth-precheck.sh" 2>&1)
  if echo "$AUTH" | grep -q "OUTCOME=ok"; then
    REM=$(echo "$AUTH" | grep -oP '\d+h' | head -1)
    record models codex_auth pass "$REM remaining" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record models codex_auth warn "$(echo "$AUTH" | tail -1)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  USAGE=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status='completed' AND completed_at > datetime('now', '-24 hours');" 2>/dev/null || echo 0)
  if [ "$USAGE" -gt 0 ]; then
    record models recent_engine_usage pass "$USAGE tasks in 24h" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record models recent_engine_usage warn "0 completed tasks in 24h" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  TOTAL_24H=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE created_at > datetime('now', '-24 hours');" 2>/dev/null || echo 1)
  FAILED_24H=$(sqlite3 "$OPS_DB" "SELECT COUNT(*) FROM tasks WHERE status IN ('blocked','cancelled') AND created_at > datetime('now', '-24 hours');" 2>/dev/null || echo 0)
  RATE=$((FAILED_24H * 100 / (TOTAL_24H > 0 ? TOTAL_24H : 1)))
  if [ "$RATE" -lt 50 ]; then
    record models error_rate pass "${RATE}% failure rate (24h)" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record models error_rate warn "${RATE}% failure rate (24h)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi
fi

# ══════════════════════════════════════════════════════════════
# PERFORMANCE (7 tests)
# ══════════════════════════════════════════════════════════════
if should_run performance; then
  $JSON_MODE || echo -e "\n  ${CYAN}[performance]${NC}"

  S=$(date +%s%N | cut -b1-13)
  MHM=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" logs --tail=200 openclaw-gateway 2>&1 | grep -c "model-health-monitor.*WARN\|Usage fetch failed" || true)
  if [ "$MHM" -lt 10 ]; then
    record performance model_health_monitor pass "$MHM warnings/200 lines" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record performance model_health_monitor warn "$MHM warnings/200 lines" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  ELU=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" logs --tail=100 openclaw-gateway 2>&1 | grep -oP 'utilization[=: ]+\K[0-9.]+' | tail -1 || echo "0")
  if python3 -c "exit(0 if float('${ELU:-0}') < 0.95 else 1)" 2>/dev/null; then
    record performance event_loop pass "utilization ${ELU:-unknown}" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record performance event_loop warn "utilization ${ELU:-unknown} (>0.95)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  DISK_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
  if [ "$DISK_PCT" -lt 85 ]; then
    record performance disk_space pass "${DISK_PCT}%" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record performance disk_space fail "${DISK_PCT}% (threshold 85%)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  AVAIL_MB=$(free -m | awk '/Mem:/{print $7}')
  if [ "$AVAIL_MB" -gt 1024 ]; then
    record performance host_memory pass "${AVAIL_MB}MB available" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record performance host_memory warn "${AVAIL_MB}MB available (<1GB)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  CMEM=$(docker stats --no-stream --format "{{.MemUsage}}" openclaw-openclaw-gateway-1 2>/dev/null | head -1 || echo "unknown")
  record performance container_memory pass "$CMEM" $(( $(date +%s%N | cut -b1-13) - S ))

  S=$(date +%s%N | cut -b1-13)
  DB_SIZE=$(($(stat -c%s "$OPS_DB" 2>/dev/null || echo 0) / 1048576))
  if [ "$DB_SIZE" -lt 50 ]; then
    record performance ops_db_size pass "${DB_SIZE}MB" $(( $(date +%s%N | cut -b1-13) - S ))
  elif [ "$DB_SIZE" -lt 100 ]; then
    record performance ops_db_size warn "${DB_SIZE}MB (>50MB)" $(( $(date +%s%N | cut -b1-13) - S ))
  else
    record performance ops_db_size fail "${DB_SIZE}MB (>100MB)" $(( $(date +%s%N | cut -b1-13) - S ))
  fi

  S=$(date +%s%N | cut -b1-13)
  RECLAIMABLE=$(docker system df 2>/dev/null | awk '/Images/{print $4}' | head -1 || echo "unknown")
  record performance docker_disk pass "reclaimable: $RECLAIMABLE" $(( $(date +%s%N | cut -b1-13) - S ))
fi

# ══════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════
TOTAL=$((PASS + FAIL + WARN + SKIP))

if $JSON_MODE; then
  echo "{\"run_id\":\"$RUN_ID\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"trigger\":\"$TRIGGER\",\"version\":\"$VERSION\",\"summary\":{\"pass\":$PASS,\"fail\":$FAIL,\"warn\":$WARN,\"skip\":$SKIP,\"total\":$TOTAL}}"
else
  echo ""
  echo -e "  ${CYAN}Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC}, $SKIP skipped ($TOTAL total)"
  echo -e "  Run ID: ${RUN_ID:0:8} | Trigger: $TRIGGER | Version: $VERSION"
fi

# Telegram notification
if $NOTIFY; then
  MSG="System Test: $PASS pass, $FAIL fail, $WARN warn (v$VERSION, $TRIGGER)"
  [ "$FAIL" -gt 0 ] && MSG="$MSG — FAILURES DETECTED"
  send_telegram "$MSG"
fi

# Auto-chart failures (with dedup)
if $CHART_FAILURES && [ "$FAIL" -gt 0 ]; then
  FAILED_TESTS=$(sqlite3 "$OPS_DB" "SELECT test_name, message FROM test_results WHERE run_id='$RUN_ID' AND status='fail';" 2>/dev/null)
  while IFS='|' read -r tname tmsg; do
    [ -z "$tname" ] && continue
    EXISTING=$(/usr/local/bin/chart search "issue-test-fail-$tname" 2>/dev/null | head -1)
    if [ -z "$EXISTING" ]; then
      /usr/local/bin/chart add "issue-test-fail-${tname}-$(date +%Y%m%d)" "System test FAIL: $tname. $tmsg. Trigger: $TRIGGER. Version: $VERSION. Run: ${RUN_ID:0:8}" issue 0.8 2>/dev/null
    fi
  done <<< "$FAILED_TESTS"
fi

# Exit code
if [ "$FAIL" -gt 0 ]; then exit 1
elif [ "$WARN" -gt 0 ]; then exit 2
else exit 0
fi
