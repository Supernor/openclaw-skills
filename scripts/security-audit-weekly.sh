#!/usr/bin/env bash
# security-audit-weekly.sh — Weekly security posture check.
# Intent: Secure [I16], Observable [I13]. Owner: Security Officer (spec-security).
#
# Checks:
#   1. File permissions on sensitive files
#   2. .env exposure (no secrets in git-tracked files)
#   3. Container user (should be node, not root)
#   4. Open ports scan
#   5. auth-profiles.json permissions
#   6. SQL injection vectors in scripts (known issue #15)
#
# Usage:
#   security-audit-weekly.sh          # run audit, output report
#   security-audit-weekly.sh --json   # JSON output
#   security-audit-weekly.sh --fix    # auto-fix permission issues

set -eo pipefail

MODE="${1:-report}"
COMPOSE_DIR="/root/openclaw"
BASE="/root/.openclaw"
PASS=0
WARN=0
FAIL=0
FIXES=0
RESULTS=()

check() {
  local status="$1" name="$2" detail="$3"
  case "$status" in
    PASS) PASS=$((PASS + 1)) ;;
    WARN) WARN=$((WARN + 1)) ;;
    FAIL) FAIL=$((FAIL + 1)) ;;
  esac
  RESULTS+=("{\"status\":\"$status\",\"check\":\"$name\",\"detail\":\"$detail\"}")
}

# 1. Sensitive file permissions
check_permissions() {
  local file="$1" expected="$2" label="$3"
  if [ ! -f "$file" ]; then
    check "WARN" "$label" "file not found: $file"
    return
  fi
  local actual
  actual=$(stat -c%a "$file" 2>/dev/null || echo "???")
  if [ "$actual" = "$expected" ]; then
    check "PASS" "$label" "permissions $actual (expected $expected)"
  else
    check "FAIL" "$label" "permissions $actual (expected $expected)"
    if [ "$MODE" = "--fix" ]; then
      chmod "$expected" "$file"
      FIXES=$((FIXES + 1))
    fi
  fi
}

check_permissions "$BASE/openclaw.json" "600" "config-perms"
check_permissions "$COMPOSE_DIR/.env" "600" "env-perms"

# Check all auth-profiles.json files
for ap in "$BASE"/agents/*/agent/auth-profiles.json; do
  [ -f "$ap" ] || continue
  agent=$(echo "$ap" | sed "s|$BASE/agents/||;s|/agent/auth-profiles.json||")
  check_permissions "$ap" "600" "auth-profiles-$agent"
done

# 2. Secrets in tracked files
if [ -d "$COMPOSE_DIR/.git" ]; then
  secrets_found=$(cd "$COMPOSE_DIR" && git diff --cached --name-only 2>/dev/null | xargs grep -l "API_KEY\|SECRET\|PASSWORD\|TOKEN" 2>/dev/null | head -5 || true)
  if [ -n "$secrets_found" ]; then
    check "FAIL" "secrets-in-git" "staged files contain secret patterns: $secrets_found"
  else
    check "PASS" "secrets-in-git" "no secrets in staged files"
  fi
fi

# 3. Container user check
container_user=$(cd "$COMPOSE_DIR" && docker compose exec -T openclaw-gateway whoami 2>/dev/null | tr -d '\r' || echo "unknown")
if [ "$container_user" = "node" ]; then
  check "PASS" "container-user" "running as node"
elif [ "$container_user" = "root" ]; then
  check "FAIL" "container-user" "running as root (should be node)"
else
  check "WARN" "container-user" "could not determine user: $container_user"
fi

# 4. Open ports (quick scan of listening ports)
open_ports=$(ss -tlnp 2>/dev/null | grep -v "^State" | awk '{print $4}' | sed 's/.*://' | sort -u | tr '\n' ',' | sed 's/,$//')
expected_ports="22,3000,3001,5000,8080,11434"
unexpected=""
for port in $(echo "$open_ports" | tr ',' '\n'); do
  if ! echo "$expected_ports" | grep -qw "$port"; then
    unexpected="${unexpected}${port},"
  fi
done
if [ -n "$unexpected" ]; then
  check "WARN" "open-ports" "unexpected ports: ${unexpected%,}"
else
  check "PASS" "open-ports" "only expected ports open: $open_ports"
fi

# 5. SQL injection check (known issue #15)
sqli_count=0
for script in "$BASE/scripts/ops-db.sh" "$BASE/scripts/reactor-ledger.sh"; do
  [ -f "$script" ] || continue
  # Look for unquoted variable interpolation in SQL
  hits=$(grep -c 'sqlite3.*\$[^"]*' "$script" 2>/dev/null || echo "0")
  sqli_count=$((sqli_count + hits))
done
if [ "$sqli_count" -gt 0 ]; then
  check "WARN" "sql-injection" "$sqli_count potential injection vectors (known issue #15)"
else
  check "PASS" "sql-injection" "no obvious injection vectors"
fi

# 6. Workspace permission sprawl
world_readable=$(find "$BASE" -maxdepth 2 -name "*.json" -perm -o+r 2>/dev/null | wc -l)
if [ "$world_readable" -gt 5 ]; then
  check "WARN" "world-readable" "$world_readable JSON files world-readable in $BASE"
else
  check "PASS" "world-readable" "$world_readable JSON files world-readable"
fi

# Output
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$MODE" = "--json" ]; then
  echo "{\"timestamp\":\"$NOW\",\"pass\":$PASS,\"warn\":$WARN,\"fail\":$FAIL,\"fixes\":$FIXES,\"checks\":[$(IFS=,; echo "${RESULTS[*]}")]}"
else
  echo "Security Audit — $NOW"
  echo "========================================"
  for r in "${RESULTS[@]}"; do
    status=$(echo "$r" | jq -r '.status')
    name=$(echo "$r" | jq -r '.check')
    detail=$(echo "$r" | jq -r '.detail')
    case "$status" in
      PASS) printf "  [PASS] %-20s %s\n" "$name" "$detail" ;;
      WARN) printf "  [WARN] %-20s %s\n" "$name" "$detail" ;;
      FAIL) printf "  [FAIL] %-20s %s\n" "$name" "$detail" ;;
    esac
  done
  echo "========================================"
  echo "Summary: $PASS pass, $WARN warn, $FAIL fail"
  [ "$FIXES" -gt 0 ] && echo "Auto-fixed: $FIXES issues"
fi

[ "$FAIL" -gt 0 ] && exit 1
exit 0
