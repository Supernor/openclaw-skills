#!/usr/bin/env bash
# === INTENT ===
# Thin wrapper over codex-login-safe (the single guarded door for Codex device logins, #1607): checks both pools, starts a GUARDED login only for a dead one.
# All login/install/identity/sync logic lives in codex-login-safe; --check never starts a login.
# codex-reauth-telegram.sh [--check] [chat_id]
#   --check   only test both pools (exit 0 both OK, 1 otherwise). SAFE to run "to test both pools": it never starts a device login or pages anyone.
#   (default) test both pools; for each dead pool run `codex-login-safe <pool> --notify telegram` (device URL+code to Robert's Telegram; the supervisor
#             installs the new login automatically when he finishes, even though this script returns in seconds).
# chat_id is accepted for backward compatibility with the executor golden-script call; Telegram delivery uses codex_auth_guard.tg_direct (robert).
# Old implementation (ran its own login): codex-reauth-telegram.sh.bak-door-20261028.
set -o pipefail

CHECK_ONLY=false
[ "${1:-}" = "--check" ] && { CHECK_ONLY=true; shift; }
LOG="/root/.openclaw/logs/codex-reauth.log"
SAFE=/root/.openclaw/scripts/codex-login-safe
source /root/openclaw/.env 2>/dev/null || true
OPS_CODEX_WEBHOOK=$(cat /root/.openclaw/ops-codex-webhook-url.txt 2>/dev/null)
[ "${CODEX_GUARD_TEST:-}" = 1 ] && OPS_CODEX_WEBHOOK=""   # test mode: never post to Discord

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOG"; }

send_notification() {   # Discord ops-codex status line (JSON built by python: no quoting bugs)
    local msg="$1"
    [ -n "$OPS_CODEX_WEBHOOK" ] || return 0
    python3 -c 'import json,sys; print(json.dumps({"content": sys.argv[1]}))' "$msg" |
        curl -sf -X POST "$OPS_CODEX_WEBHOOK" -H "Content-Type: application/json" -d @- >/dev/null 2>&1 || true
}

# pool health: env sets CODEX_HOME (F4: `timeout 10 HOME=... codex` was invalid syntax, rc 127, so pool B always looked dead)
check_pool() {   # $1 = CODEX_HOME dir
    ( cd /root/openclaw && env CODEX_HOME="$1" timeout 10 codex exec --skip-git-repo-check "echo ok" >/dev/null 2>&1 )
}

log "Checking Codex pool status (check_only=$CHECK_ONLY)..."
POOL_A_OK=false; POOL_B_OK=false; POOL_B_CONFIGURED=false
check_pool /root/.codex && POOL_A_OK=true
log "Pool A: $($POOL_A_OK && echo VALID || echo 'EXPIRED or failing')"
if [ -d /root/.codex-pool-b ]; then
    POOL_B_CONFIGURED=true
    check_pool /root/.codex-pool-b && POOL_B_OK=true
    log "Pool B: $($POOL_B_OK && echo VALID || echo 'EXPIRED or failing')"
else
    log "Pool B: not configured (no /root/.codex-pool-b)"; POOL_B_OK=true
fi

if $POOL_A_OK && $POOL_B_OK; then
    log "Both pools are VALID - no reauth needed"
    echo "Pool A: OK  Pool B: OK"
    exit 0
fi
if $CHECK_ONLY; then
    echo "Pool A: $($POOL_A_OK && echo OK || echo NEEDS_REAUTH)  Pool B: $($POOL_B_OK && echo OK || echo NEEDS_REAUTH)  (check only: no login started)"
    exit 1
fi

send_notification "Codex pool status: Pool A: $($POOL_A_OK && echo OK || echo NEEDS REAUTH), Pool B: $($POOL_B_OK && echo OK || echo NEEDS REAUTH). Starting guarded login(s) via codex-login-safe."
RC=0
for pair in "pool-a:$POOL_A_OK" "pool-b:$POOL_B_OK"; do
    pool="${pair%%:*}"; ok="${pair##*:}"
    [ "$ok" = true ] && continue
    OUT=$("$SAFE" "$pool" --notify telegram 2>>"$LOG") || RC=1
    log "codex-login-safe $pool -> $(echo "$OUT" | python3 -c 'import json,sys
try:
    d=json.loads(sys.stdin.read().strip().splitlines()[-1]); print("ok=%s in_flight=%s status_file=%s err=%s" % (d.get("ok"), d.get("in_flight"), d.get("status_file"), d.get("error")))
except Exception: print("unparseable output")')"
    echo "$OUT" | python3 -c 'import json,sys
d=json.loads(sys.stdin.read().strip().splitlines()[-1]); d.pop("code",None); print(json.dumps(d))' 2>/dev/null   # stdout goes into the ops task outcome: no device code there
done
exit $RC
