#!/usr/bin/env bash
# backup-suite.sh — Golden script for Repo-Man nightly GitHub backup push
#
# WHO:  Called by host-ops-executor via "backup-suite" handler
# WHAT: Runs all 3 GitHub backup scripts inside the container, then verifies
# WHEN: Nightly at 3:30am UTC (dispatched by post-backup-dispatch.sh)
# WHY:  Zero-token execution — no LLM needed for routine push operations.
#       Previous approach used codex-run which depends on Codex OAuth health.
#       This golden script always works regardless of model availability.
#
# DESIGN: Runs scripts inside the Docker container (where gh auth and git
#         credential helpers are configured). Captures JSON output from each,
#         aggregates into a summary. Non-zero exit = at least one backup failed.
#
# TROUBLESHOOTING:
#   - "docker compose exec" fails → container not running. Check: docker compose ps
#   - "permission denied" on scripts → container user (node/1000) can't execute.
#     Fix: docker compose exec --user root openclaw-gateway chmod +x /path/to/script
#   - "push failed" in any backup → Git auth broken. Run github-guardian skill.
#   - All 3 "no changes" → normal if nothing changed since last push.
#
# CHARTS: chart read skill-backup-suite-v1, chart read procedure-update-openclaw

set -euo pipefail

COMPOSE_FILE="/root/openclaw/docker-compose.yml"
LAST_RUN="/root/.openclaw/workspace-spec-github/LAST_RUN.md"
RESULTS=""
FAILURES=0
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

run_in_container() {
    local script="$1"
    docker compose -f "$COMPOSE_FILE" exec -T openclaw-gateway bash -c "$script" 2>&1
}

# Runs a script on the HOST (not in container). Used for vps-backup which needs
# read access to /usr/local/bin, /etc/systemd/system, root's crontab, and
# /root/.claude — none of which are bind-mounted into the gateway container.
run_on_host() {
    local script="$1"
    bash "$script" 2>&1
}

echo "=== Backup Suite — $TIMESTAMP ==="

# --- 1. env-backup (push .env key names to openclaw-config) ---
echo "[1/5] env-backup..."
ENV_OUT=$(run_in_container "/home/node/.openclaw/scripts/env-backup.sh")
ENV_STATUS=$(echo "$ENV_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','ERROR'))" 2>/dev/null || echo "ERROR")
ENV_PUSHED=$(echo "$ENV_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pushed','?'))" 2>/dev/null || echo "?")

if [ "$ENV_STATUS" = "FATAL" ]; then
    echo "FATAL: env-backup detected possible secret leak. Aborting entire suite."
    echo "$ENV_OUT"
    exit 2
fi
[ "$ENV_STATUS" != "PASS" ] && FAILURES=$((FAILURES+1))
RESULTS="${RESULTS}env-backup: ${ENV_STATUS} (pushed=${ENV_PUSHED})\n"
echo "  -> $ENV_STATUS (pushed=$ENV_PUSHED)"

# --- 2. skills-backup (push skills/hooks/scripts to openclaw-skills) ---
echo "[2/5] skills-backup..."
SKILLS_OUT=$(run_in_container "/home/node/.openclaw/scripts/skills-backup.sh")
SKILLS_STATUS=$(echo "$SKILLS_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','ERROR'))" 2>/dev/null || echo "ERROR")
SKILLS_PUSHED=$(echo "$SKILLS_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pushed','?'))" 2>/dev/null || echo "?")
[ "$SKILLS_STATUS" != "PASS" ] && FAILURES=$((FAILURES+1))
RESULTS="${RESULTS}skills-backup: ${SKILLS_STATUS} (pushed=${SKILLS_PUSHED})\n"
echo "  -> $SKILLS_STATUS (pushed=$SKILLS_PUSHED)"

# --- 3. ws-backup (push workspace MD files to openclaw-workspace) ---
echo "[3/5] workspace-backup..."
WS_OUT=$(run_in_container "/home/node/.openclaw/scripts/ws-backup.sh" 2>&1 | grep -v "Permission denied" || true)
WS_STATUS=$(echo "$WS_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','ERROR'))" 2>/dev/null || echo "ERROR")
WS_PUSHED=$(echo "$WS_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pushed','?'))" 2>/dev/null || echo "?")
[ "$WS_STATUS" != "PASS" ] && FAILURES=$((FAILURES+1))
RESULTS="${RESULTS}workspace-backup: ${WS_STATUS} (pushed=${WS_PUSHED})\n"
echo "  -> $WS_STATUS (pushed=$WS_PUSHED)"

# --- 4. vps-backup (push rebuild-the-VPS artifacts to openclaw-vps) ---
#       Runs ON HOST (not container) — needs /usr/local/bin, /etc/systemd, etc.
#       Aborts on secret-pattern hits via vps-backup-secrets-guard.sh.
echo "[4/5] vps-backup..."
VPS_OUT=$(run_on_host "/root/.openclaw/scripts/vps-backup.sh")
VPS_STATUS=$(echo "$VPS_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','ERROR'))" 2>/dev/null || echo "ERROR")
VPS_PUSHED=$(echo "$VPS_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pushed','?'))" 2>/dev/null || echo "?")
# BLOCKED is a guard-fired abort — bad enough to count as a failure (it means
# new secrets entered files the script tries to publish). PASS is the good case.
[ "$VPS_STATUS" != "PASS" ] && FAILURES=$((FAILURES+1))
RESULTS="${RESULTS}vps-backup: ${VPS_STATUS} (pushed=${VPS_PUSHED})\n"
echo "  -> $VPS_STATUS (pushed=$VPS_PUSHED)"

# --- 5. repo-health (verify all 4 GitHub repos are fresh) ---
echo "[5/5] repo-health..."
HEALTH_OUT=$(run_in_container "/home/node/.openclaw/scripts/repo-health.sh")
HEALTH_STATUS=$(echo "$HEALTH_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','ERROR'))" 2>/dev/null || echo "ERROR")
STALE=$(echo "$HEALTH_OUT" | python3 -c "import sys,json; print(sum(1 for r in json.load(sys.stdin).get('repos',[]) if r.get('stale')))" 2>/dev/null || echo "?")
RESULTS="${RESULTS}repo-health: ${HEALTH_STATUS} (stale=${STALE})\n"
echo "  -> $HEALTH_STATUS (stale repos: $STALE)"

# --- 5. Update LAST_RUN.md audit trail ---
if [ -f "$LAST_RUN" ]; then
    if [ "$FAILURES" -eq 0 ]; then
        echo "$TIMESTAMP | backup-suite | PASS | env=${ENV_STATUS} skills=${SKILLS_STATUS} ws=${WS_STATUS} vps=${VPS_STATUS} repos=${HEALTH_STATUS}" >> "$LAST_RUN"
    else
        echo "$TIMESTAMP | backup-suite | FAIL | ${FAILURES} failures: env=${ENV_STATUS} skills=${SKILLS_STATUS} ws=${WS_STATUS} vps=${VPS_STATUS}" >> "$LAST_RUN"
    fi
fi

# --- Summary ---
echo ""
echo "=== Summary ==="
echo -e "$RESULTS"
if [ "$FAILURES" -eq 0 ]; then
    echo "RESULT: ALL PASSED"
    exit 0
else
    echo "RESULT: ${FAILURES} FAILURE(S)"
    exit 1
fi
