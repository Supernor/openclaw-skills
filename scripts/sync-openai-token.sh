#!/usr/bin/env bash
# sync-openai-token.sh — keep the gateway's openai/gpt-5.5 auth fresh from the valid host Codex token.
#
# WHY THIS EXISTS (2026-06-29): OpenClaw 2026.6.10 migrated agent auth from auth-profiles.json into a
# per-agent SQLite store, which silently broke the old sync-codex-auth.sh (it wrote the now-dead
# auth-profiles.json path). The gateway's openai OAuth tokens then expired and Relay/Eoin fell back to
# nemotron while the Bridge still showed "pools healthy" (manual-1782765015). The SANCTIONED modern path
# (per `openclaw models auth login` itself) is `openclaw models auth paste-token` — it writes the current
# store wherever it lives now, no hardcoded path. paste-token stores an ACCESS token (no refresh), so this
# runs on a schedule to re-paste the host's always-fresh token before the ~7-day access token expires.
# No gateway restart needed — agents pick up the new token on next dispatch (verified 2026-06-29).
#
# Host token stays fresh because the Codex CLI auto-refreshes ~/.codex on use. If the HOST token is ALSO
# expired, this cannot fix it (a real OAuth re-auth needs Robert's browser: device-code) — it alerts instead.
#
# 2026-10-07 REAUTH-FIX (deferred #251): now the ONE sync path for BOTH pools, called by the cron, the
# event-driven watcher (codex-auth-watcher.sh) and the 06:00 precheck. Changes vs before:
#  - restarts the gateway ONLY after a DETECTED token change (sha256 of the host token vs last paste,
#    state in $STATE_DIR) instead of on every run; a pending-restart marker survives a busy-blocked restart
#    and is retried (OPENAI_SYNC_RESTART_ONLY=1) - forced after 30 min since dead auth is the emergency case;
#  - restart goes through gateway-restart-safe.sh (busy check + notify + health poll);
#  - dead-token alert names the pool and follows the Error Message Policy; "out of credits" is diagnosed
#    separately by codex-lane-health-probe.py (it hits BOTH pools - same workspace - a re-auth cannot fix it).
# Test hook: OPENAI_SYNC_DRY_RUN=1 (no docker/telegram/restart, logs what would happen); OPENAI_SYNC_STATE_DIR.
set -uo pipefail

COMPOSE="docker compose -f /root/openclaw/docker-compose.yml"
HOST_AUTH="${OPENAI_SYNC_HOST_AUTH:-$HOME/.codex/auth.json}"
AGENTS="${OPENAI_SYNC_AGENTS:-relay eoin main}"
PROFILE="${OPENAI_SYNC_PROFILE:-openai:default}"
LOG="/root/.openclaw/logs/sync-openai-token.log"
STATE_DIR="${OPENAI_SYNC_STATE_DIR:-/root/.openclaw/state/openai-sync}"
DRY="${OPENAI_SYNC_DRY_RUN:-}"
[ -n "$DRY" ] && LOG="${OPENAI_SYNC_LOG:-/tmp/sync-openai-token.dryrun.log}"
mkdir -p "$STATE_DIR"
case "$PROFILE" in openai:pool-b) POOL=pool-b;; openai:default) POOL=pool-a;; *) POOL="$PROFILE";; esac
SAFE_RESTART="${OPENAI_SYNC_SAFE_RESTART:-/root/.openclaw/scripts/gateway-restart-safe.sh}"
PENDING="$STATE_DIR/restart-pending"        # line 1 = epoch first requested; later lines = pool names
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$POOL] $1" | tee -a "$LOG"; }

# One sync at a time across cron + watcher + precheck (both pools share the gateway restart).
exec 8>"$STATE_DIR/sync.lock"
flock -w 300 8 || { log "could not get sync lock in 300s - another sync is running; exiting"; exit 1; }

tg_direct() {   # gateway-independent alert (Operational Rule 3). 2026-10-28 (#1607): delivery is now VERIFIED + LOGGED
    # (HTTP status -> $LOG and kv codex_auth_tg_last) via codex_auth_guard.py; it used to be curl >/dev/null || true (silent).
    [ -n "$DRY" ] && { log "DRY-RUN telegram: $1"; return 0; }
    local out
    out=$(python3 -I /root/.openclaw/scripts/codex_auth_guard.py send --source sync-openai-token -- "$1" 2>&1); local rc=$?
    log "telegram alert rc=$rc: $(printf %s "$out" | tail -1 | cut -c1-200)"
    return 0
}
tg_direct_gated() {   # $1 = kv gate key, rest = text. Re-pages at most once per 24h until cleared on a good sync.
    local key="$1"; shift
    [ -n "$DRY" ] && { log "DRY-RUN telegram (gated $key): $1"; return 0; }
    local out
    out=$(python3 -I /root/.openclaw/scripts/codex_auth_guard.py send --source sync-openai-token --gate-key "$key" --gate-hours 24 -- "$1" 2>&1); local rc=$?
    log "telegram alert (gated $key) rc=$rc: $(printf %s "$out" | tail -1 | cut -c1-200)"
    return 0
}

# Restart the gateway if a restart is pending (set by a detected token change). Graceful path first.
do_pending_restart() {
    [ -f "$PENDING" ] || { log "no restart pending"; return 0; }
    local since age rc pools
    since=$(head -1 "$PENDING"); age=$(( $(date +%s) - ${since:-$(date +%s)} ))
    pools=$(tail -n +2 "$PENDING" | sort -u | tr '\n' ' ')
    if [ -n "$DRY" ]; then log "DRY-RUN: would run $SAFE_RESTART 8561305605 'openai auth token changed ($pools)' (pending ${age}s)"; return 0; fi
    log "Restarting gateway to load pasted tokens (boot-only auth load; pending ${age}s; pools: $pools)..."
    "$SAFE_RESTART" 8561305605 "openai auth token changed ($pools) - gateway loads auth at boot only" >>"$LOG" 2>&1; rc=$?
    if [ "$rc" -eq 2 ] && [ "$age" -ge 1800 ]; then
        log "Restart blocked as busy for ${age}s (>=30min) - forcing: dead/rotated auth is the emergency case."
        "$SAFE_RESTART" 8561305605 "openai auth token changed - forced after 30min busy" --force >>"$LOG" 2>&1; rc=$?
    fi
    if [ "$rc" -eq 0 ]; then rm -f "$PENDING"; log "Gateway restarted and healthy."; return 0; fi
    if [ "$rc" -eq 2 ]; then log "Restart deferred (agents busy); marker kept - watcher retries every 5 min, forced at 30 min."; return 2; fi
    log "Gateway restart FAILED (rc=$rc) - pasted tokens NOT live. Marker kept. Tried: gateway-restart-safe.sh. Not tried: docker compose down+up. Check docker."
    tg_direct "OpenAI auth: gateway restart FAILED (rc=$rc) after a token change ($pools). WHAT: new token pasted but the gateway still serves its boot-time (old) auth. TRIED: gateway-restart-safe.sh. NOT TRIED: docker compose down+up, docker logs. WORKED BEFORE: plain docker compose restart openclaw-gateway (Jul 20 repair)."
    return 1
}

if [ -n "${OPENAI_SYNC_RESTART_ONLY:-}" ]; then do_pending_restart; exit $?; fi

# Extract the host access token + remaining hours from the JWT exp; empty token => not valid.
read -r TOKEN HOURS < <(python3 -c "
import json, base64, time, sys
try:
    a=json.load(open('$HOST_AUTH')); t=a.get('tokens',a); tok=t.get('access_token','')
    if not tok or '.' not in tok: print('NONE', 0); sys.exit()
    p=tok.split('.')[1]; p+='='*(4-len(p)%4)
    exp=json.loads(base64.urlsafe_b64decode(p)).get('exp',0)
    rem=int((exp-time.time())/3600)
    print(tok if rem>0 else 'NONE', max(0,rem))
except Exception:
    print('NONE', 0)
" 2>/dev/null)
# 2026-10-07: the python used to print an EMPTY token as ' 0', which bash 'read' collapsed to TOKEN='0' -> a dead
# host token was treated as valid and the dead-token alert below never fired. 'NONE' sentinel fixes it.
[ "$TOKEN" = "NONE" ] && TOKEN=""

if [ -z "$TOKEN" ]; then
    log "HOST TOKEN EXPIRED/MISSING ($HOST_AUTH) — cannot sync. Needs a device-code re-auth (Robert)."
    echo "RESULT_LABEL: needs_reauth"   # cron-wrapper surfaces this on the Bridge cron-health view
    tg_direct_gated "openai_token_dead_page_${POOL}" "OpenAI $POOL TOKEN DEAD: the host Codex token ($HOST_AUTH) is expired/missing, so sync cannot refresh the gateway; agents on this pool fall back to nemotron. This is ONE pool's token, not credits (credits-exhausted hits BOTH pools at once and is reported separately by the Codex lane probe). HISTORY: the 04:20/04:25 syncs and the auth-file watcher only copy a still-valid token; a dead refresh token has never been fixable without a browser. TRIED: nothing automatic can fix this. NOT TRIED: the guarded login for $POOL (the Bridge Reauth button calls the same door). WORKED BEFORE: device re-auth by Robert, Jul 20 2026 (then sync + gateway restart); Oct 28 2026 16:58 EDT. FIX: ! /root/.openclaw/scripts/codex-login-safe $POOL   (guarded: runs the login in a scratch dir and installs only on success, so your current login is never deleted; finish the code on your phone, signed in as the pool's own account). Re-pages at most once per 24h until reauth."
    exit 1
fi

# 2026-10-07 IDENTITY GATE (Grok letter D): refuse to paste a token whose login is not the pool's intended
# account (Oct 5 incident: both pools ended up on the gmail login). Fails OPEN if identity can't be decoded.
IDV=$(python3 - "$HOST_AUTH" "$POOL" <<'PYEOF' 2>/dev/null
import json, base64, sys
def claims(t):
    try:
        p = t.split(".")[1]; p += "=" * ((4 - len(p) % 4) % 4)
        return json.loads(base64.urlsafe_b64decode(p))
    except Exception:
        return {}
def email(c):
    pr = c.get("https://api.openai.com/profile")
    if isinstance(pr, dict) and pr.get("email"): return pr["email"]
    return c.get("email") or ""
try:
    a = json.load(open(sys.argv[1])); t = a.get("tokens", a)
    got = (email(claims(t.get("access_token", ""))) or email(claims(t.get("id_token", "")))).lower()
    exp = json.load(open("/root/.openclaw/docs/codex-pool-intended-identities.json"))["pools"].get(sys.argv[2], {}).get("expected_email", "").lower()
    print("MISMATCH %s %s" % (got, exp) if got and exp and got != exp else "OK")
except Exception:
    print("OK")
PYEOF
)
if [ "${IDV%% *}" = "MISMATCH" ]; then
    set -- $IDV
    log "IDENTITY MISMATCH for $POOL: token belongs to $2 but this pool is $3 - REFUSING to paste."
    echo "RESULT_LABEL: identity_mismatch"
    tg_direct "OpenAI $POOL IDENTITY MISMATCH: sync refused. WHAT: $HOST_AUTH holds a login for $2 but $POOL must be $3 (docs/codex-pool-intended-identities.json). Pasting it would put two pools on one seat. HISTORY: Oct 5 2026 both pools ended up on the gmail login after a device-flow login in the wrong browser profile (auth.json.bak-20261005-gmailwrong). TRIED: nothing pasted, gateway untouched. NOT TRIED: re-run the device login signed in as $3. WORKED BEFORE: Oct 5 fix - re-login as the correct account then sync."
    exit 1
fi

[ -z "$DRY" ] && python3 -I /root/.openclaw/scripts/codex_auth_guard.py kv-clear "openai_token_dead_page_${POOL}" >/dev/null 2>&1   # token healthy: next death pages immediately
log "Host token valid (${HOURS}h left). Pasting $PROFILE for: $AGENTS"
ok=0; fail=0
for agent in $AGENTS; do
    if [ -n "$DRY" ]; then log "  DRY-RUN would paste $PROFILE for $agent"; ok=$((ok+1)); continue; fi
    if echo "$TOKEN" | timeout 60 $COMPOSE exec -T openclaw-gateway \
         openclaw models auth --agent "$agent" paste-token --provider openai \
         --profile-id "$PROFILE" --expires-in "${HOURS}h" >/dev/null 2>&1; then
        log "  ✓ $agent"; ok=$((ok+1))
    else
        log "  ✗ $agent (paste failed)"; fail=$((fail+1))
    fi
done
log "Done: $ok ok, $fail failed."
# Change detection: restart only when the host token differs from the one last pasted for this profile.
# (Restart IS mandatory after a change - scar gateway-auth-wrong-door-20260720 - but not on every run.)
SHA=$(printf %s "$TOKEN" | sha256sum | cut -d' ' -f1)
SHAFILE="$STATE_DIR/last-pasted-${POOL}.sha256"
PREV=$(cat "$SHAFILE" 2>/dev/null)
if [ "$ok" -gt 0 ]; then
    if [ "$SHA" != "$PREV" ]; then
        log "TOKEN CHANGE DETECTED (sha ${SHA:0:12} vs last ${PREV:0:12}) - gateway restart required."
        [ -f "$PENDING" ] || date +%s > "$PENDING"
        echo "$POOL" >> "$PENDING"
        echo "$SHA" > "$SHAFILE"
    else
        log "Token unchanged since last paste - no new restart requested."
    fi
fi
# Skippable for callers that batch syncs: OPENAI_SYNC_NO_RESTART=1 (marker persists; the next un-suppressed
# run - e.g. the 04:25 pool-b cron, the watcher's 5-min retry - performs the restart).
if [ -z "${OPENAI_SYNC_NO_RESTART:-}" ]; then do_pending_restart; fi
[ "$fail" -eq 0 ]
