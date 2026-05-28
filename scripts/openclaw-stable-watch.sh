#!/usr/bin/env bash
# openclaw-stable-watch.sh — Watch for a newer OpenClaw STABLE release than the one
# deployed, and alert. Owner: Repo-Man (spec-github).
#
# WHY: OpenClaw ships a stable release ~every 2 days (it is the fastest-growing repo
# in GitHub history, ~535 commits/day, mostly AI-authored — see chart
# ref-openclaw-update-understanding). We deliberately track STABLE releases, not
# bleeding-edge main. This watcher tells Robert + Repo-Man the moment a newer stable
# is cut, so the update can be landed deliberately via the gated openclaw-update
# handler. It NEVER changes anything — detect + alert only.
#
# DESIGN (mirrors api-health-probe.sh):
#  - Zero token cost: pure git + sqlite, no model calls (never poll a model).
#  - State-change only: alerts once per NEW stable version, not every run (no spam).
#  - Direct Telegram: bypasses the gateway so the alert works even if it is down.
#  - No downgrade noise: only flags a stable that is NEWER (by version) than running.
#  - Writes status to kv so Bridge can show it.
# Usage: openclaw-stable-watch.sh [--quiet]   (cron uses --quiet)
set -uo pipefail
REPO="/root/openclaw"
OPS_DB="/root/.openclaw/ops.db"
ENV_FILE="$REPO/.env"
STATE_FILE="/root/.openclaw/openclaw-stable-watch-state.json"
LOG="/root/.openclaw/logs/openclaw-stable-watch.log"
QUIET=false; [ "${1:-}" = "--quiet" ] && QUIET=true
mkdir -p "$(dirname "$LOG")"
log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [stable-watch] $1" >> "$LOG"; }

telegram_direct() {
  local MSG="$1" TOKEN TARGET
  TOKEN=$(grep '^TELEGRAM_BOT_TOKEN_ROBERT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d "\"'")
  [ -z "$TOKEN" ] && TOKEN=$(grep '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | tr -d "\"'")
  TARGET=$(telegram-resolve robert 2>/dev/null || echo 8561305605)
  [ -n "$TOKEN" ] && curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="$TARGET" -d text="$MSG" >/dev/null 2>&1
}

kv_set() { sqlite3 "$OPS_DB" "INSERT OR REPLACE INTO kv (key,value,updated_at) VALUES ('$1','$2',strftime('%Y-%m-%dT%H:%M:%SZ','now'));" 2>>"$LOG" || true; }

cd "$REPO" || { log "repo missing"; exit 1; }
git fetch origin --tags -q 2>/dev/null || log "fetch had warnings (continuing)"

NEWEST_TAG=$(git tag -l 'v*' --sort=-creatordate | grep -vE 'alpha|beta|rc' | head -1)
[ -z "$NEWEST_TAG" ] && { log "no stable tag found"; exit 0; }
STABLE_VER=$(git show "$NEWEST_TAG:package.json" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin)['version'])" 2>/dev/null || echo "0")
CUR_VER=$(python3 -c "import json;print(json.load(open('package.json'))['version'])" 2>/dev/null || echo "0")
LAST=$(python3 -c "import json;print(json.load(open('$STATE_FILE')).get('last_alerted',''))" 2>/dev/null || echo "")

# newer = STABLE_VER strictly greater than CUR_VER (version sort)
LOWEST=$(printf '%s\n%s\n' "$CUR_VER" "$STABLE_VER" | sort -V | head -1)
NEWER=false
[ "$STABLE_VER" != "$CUR_VER" ] && [ "$LOWEST" = "$CUR_VER" ] && NEWER=true

kv_set "openclaw_update_status" "running=$CUR_VER newest_stable=$STABLE_VER newer_available=$NEWER checked=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if $NEWER; then
  if [ "$LAST" = "$STABLE_VER" ]; then
    log "newer stable $STABLE_VER available but already alerted — quiet"
  else
    log "NEW stable $NEWEST_TAG ($STABLE_VER); running $CUR_VER — alerting Robert + flagging Repo-Man"
    telegram_direct "OpenClaw: newer STABLE release ${NEWEST_TAG} (${STABLE_VER}) is out — you are running ${CUR_VER}. Repo-Man owns the check. Landing it is deliberate + gated (openclaw-update: stop, build, recreate, hash-gated post-test, auto-rollback). Ask Repo-Man to verify and recommend, or confirm an update when ready."
    python3 -c "import json;json.dump({'last_alerted':'$STABLE_VER','newest_stable_tag':'$NEWEST_TAG','running':'$CUR_VER','newer_available':True,'ts':'$(date -u +%Y-%m-%dT%H:%M:%SZ)'},open('$STATE_FILE','w'))"
  fi
else
  log "no newer stable (newest $STABLE_VER <= running $CUR_VER) — quiet"
  python3 -c "import json;json.dump({'last_alerted':'$LAST','newest_stable_tag':'$NEWEST_TAG','newest_stable_ver':'$STABLE_VER','running':'$CUR_VER','newer_available':False,'ts':'$(date -u +%Y-%m-%dT%H:%M:%SZ)'},open('$STATE_FILE','w'))" 2>>"$LOG" || true
fi

$QUIET || echo "running=$CUR_VER  newest_stable=$STABLE_VER ($NEWEST_TAG)  newer_available=$NEWER"
