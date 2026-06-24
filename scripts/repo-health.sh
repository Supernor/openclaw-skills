#!/bin/bash
# repo-health.sh — Verify all 4 GitHub backup repos are reachable + fresh, and the
# vault has its secrets. Outputs structured JSON. Zero LLM tokens needed.
#
# SELF-EXPLAINING WARNINGS (2026-06-24): when status != PASS, the output carries a
# top-level "warnings" array AND a one-line "summary" stating EXACTLY what tripped
# it and what to do — no need to cross-reference repos[]/secrets{} to find out why.
# (Robert: "a warning shouldn't need exploration to understand.")
#
# 2026-05-29: added openclaw-vps (host-side rebuild artifacts; pushed nightly via
# vps-backup.sh step 4/5 of backup-suite.sh). See chart procedure-vps-backup-pipeline-20260529.
set -euo pipefail

REPOS=("openclaw-config" "openclaw-workspace" "openclaw-skills" "openclaw-vps")
# Vault is allowed to GROW (new services add secrets). A real problem is secrets
# DISAPPEARING, so we warn only when the count drops BELOW this floor — not on a
# higher count. Floor = the critical keys that must always be backed up.
MIN_SECRETS=15
STALE_DAYS=7
NOW=$(date +%s)
STALE_SECONDS=$((STALE_DAYS * 86400))

RESULTS="["
WARNINGS="["   # plain-English reasons, JSON-string array
FIRST=true
WFIRST=true
ALL_OK=true

add_warning() {  # $1 = human-readable reason
  if ! $WFIRST; then WARNINGS+=","; fi
  WFIRST=false
  # escape double-quotes/backslashes for JSON
  local msg="${1//\\/\\\\}"; msg="${msg//\"/\\\"}"
  WARNINGS+="\"$msg\""
  ALL_OK=false
}

for repo in "${REPOS[@]}"; do
  if ! $FIRST; then RESULTS+=","; fi
  FIRST=false

  REPO_DATA=$(gh api "repos/Supernor/$repo" 2>/dev/null || echo '{"error":true}')
  if echo "$REPO_DATA" | jq -e '.error' >/dev/null 2>&1; then
    RESULTS+='{"repo":"'"$repo"'","reachable":false,"status":"ERROR"}'
    add_warning "repo '$repo' is UNREACHABLE via gh api — check gh auth (gh auth status) or that the repo still exists at Supernor/$repo."
    continue
  fi

  PUSHED_AT=$(echo "$REPO_DATA" | jq -r '.pushed_at // "unknown"')
  PRIVATE=$(echo "$REPO_DATA" | jq -r '.private')

  if [ "$PUSHED_AT" != "unknown" ]; then
    PUSH_EPOCH=$(date -d "$PUSHED_AT" +%s 2>/dev/null || echo 0)
    AGE_SECONDS=$((NOW - PUSH_EPOCH))
    AGE_DAYS=$((AGE_SECONDS / 86400))
    STALE=$( [ $AGE_SECONDS -gt $STALE_SECONDS ] && echo true || echo false )
  else
    AGE_DAYS=-1
    STALE=true
  fi

  if $STALE; then
    add_warning "repo '$repo' is STALE — last push ${AGE_DAYS}d ago (> ${STALE_DAYS}d threshold). The nightly backup for it may be failing; check the matching *-backup.sh and 'gh auth status'."
  fi

  RESULTS+='{"repo":"'"$repo"'","reachable":true,"private":'"$PRIVATE"',"pushed_at":"'"$PUSHED_AT"'","age_days":'"$AGE_DAYS"',"stale":'"$STALE"'}'
done
RESULTS+="]"

# Vault secrets: count + floor check, with a clear reason on failure.
SECRETS_COUNT=$(gh secret list --repo Supernor/openclaw-config --json name 2>/dev/null | jq 'length' 2>/dev/null || echo -1)
if [ "$SECRETS_COUNT" -lt 0 ]; then
  add_warning "could not read vault secrets (gh secret list failed) — likely gh auth/token problem; run 'gh auth status' and check GH_TOKEN."
  SECRETS_OK=false
elif [ "$SECRETS_COUNT" -lt "$MIN_SECRETS" ]; then
  add_warning "vault has only $SECRETS_COUNT secrets, below the expected floor of $MIN_SECRETS — a secret may have been deleted from Supernor/openclaw-config. Compare 'gh secret list --repo Supernor/openclaw-config' against the canonical keys in key-drift-check.sh."
  SECRETS_OK=false
else
  SECRETS_OK=true   # count >= floor; a higher count is fine (vault grew)
fi

# Local log health
LOG="/home/node/.openclaw/workspace-spec-github/logs/repo-man.log"
if [ -f "$LOG" ]; then
  LOG_LINES=$(wc -l < "$LOG"); LOG_SIZE=$(stat -c%s "$LOG" 2>/dev/null || echo 0); LOG_EXISTS=true
else
  LOG_LINES=0; LOG_SIZE=0; LOG_EXISTS=false
fi

WARNINGS+="]"
STATUS=$( $ALL_OK && echo "PASS" || echo "WARN" )
if $ALL_OK; then
  SUMMARY="all ${#REPOS[@]} backup repos reachable + fresh (< ${STALE_DAYS}d); vault has $SECRETS_COUNT secrets (>= $MIN_SECRETS)."
else
  # join the warning strings into one readable summary line
  SUMMARY=$(echo "$WARNINGS" | jq -r 'join("  |  ")' 2>/dev/null || echo "see warnings[]")
fi

cat << EOF
{
  "status": "$STATUS",
  "summary": "$(echo "$SUMMARY" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "warnings": $WARNINGS,
  "repos": $RESULTS,
  "secrets": {"count": $SECRETS_COUNT, "floor": $MIN_SECRETS, "ok": ${SECRETS_OK:-false}},
  "local_log": {"exists": $LOG_EXISTS, "lines": $LOG_LINES, "bytes": $LOG_SIZE},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
