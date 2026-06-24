#!/usr/bin/env bash
# vps-backup.sh — push the rebuild-the-VPS artifacts to Supernor/openclaw-vps.
#
# Runs ON THE HOST (not in container) because it needs read access to
# /usr/local/bin/, /etc/systemd/system/, root's crontab, and /root/.claude/.
# Same orchestration cadence as env-backup.sh / ws-backup.sh / skills-backup.sh
# (called nightly at 3:30 UTC by backup-suite.sh).
#
# Structured JSON output on success (same shape as the other three).
# Calls vps-backup-secrets-guard.sh before push; aborts if the guard fires.
#
# See:
#   /root/.claude/plans/i-would-like-to-cheerful-bumblebee.md — plan that
#     created this script
#   chart procedure-vps-backup-pipeline-* — operational doc

set -eo pipefail

# --- Config ---
REPO_PATH="/root/.openclaw/repos/openclaw-vps"
REPO_URL_NOAUTH="https://github.com/Supernor/openclaw-vps.git"
STAGE="${REPO_PATH}"     # we stage directly into the repo (atomicity via git)
LOG="/root/.openclaw/logs/vps-backup.log"
EXIT_LOG="/root/.openclaw/scripts/vps-backup-exit.log"
GUARD="/root/.openclaw/scripts/vps-backup-secrets-guard.sh"

mkdir -p "$(dirname "$LOG")" "$(dirname "$REPO_PATH")"

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "[$(ts)] $*" >> "$LOG"; }

die() {
  log "FATAL: $*"
  echo "{\"status\":\"ERROR\",\"message\":$(printf '%s' "$*" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')}"
  echo "1" > "$EXIT_LOG"
  exit 1
}

log "vps-backup start"

# --- Preflight ---
command -v git    >/dev/null 2>&1 || die "git not found"
command -v rsync  >/dev/null 2>&1 || die "rsync not found"
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not found"
[ -x "$GUARD" ] || die "secrets guard not executable at $GUARD"

# --- GitHub auth: clean URL + gh credential helper (DYNAMIC token).
#     Previously this extracted a STATIC PAT (ghp_...) from another repo's remote
#     URL and embedded it as x-access-token@github.com — the static-token
#     anti-pattern that silently broke on the 2026-06-24 auth rotation/lockout.
#     Now git resolves the LIVE token via the gh credential helper (configured by
#     `gh auth setup-git`), so there is no static token to go stale.
#     Chart: fix-github-token-dynamic-20260624. ---
REPO_URL_AUTH="$REPO_URL_NOAUTH"

# --- Clone or fast-forward ---
if [ ! -d "$REPO_PATH/.git" ]; then
  log "cloning $REPO_URL_NOAUTH into $REPO_PATH (first run)"
  rm -rf "$REPO_PATH"  # ensure empty
  if ! git clone --quiet "$REPO_URL_AUTH" "$REPO_PATH" 2>>"$LOG"; then
    # Empty repo case — clone fails with "remote HEAD refers to nonexistent ref".
    # Initialize fresh and set remote.
    log "clone returned empty; initializing local repo and setting remote"
    mkdir -p "$REPO_PATH"
    git -C "$REPO_PATH" init -q -b main
    git -C "$REPO_PATH" remote add origin "$REPO_URL_AUTH"
  fi
else
  log "repo present; fetching latest"
  git -C "$REPO_PATH" fetch --quiet origin 2>>"$LOG" || true
  git -C "$REPO_PATH" pull --quiet --ff-only origin main 2>>"$LOG" || true
fi

# Set local commit identity (the existing 3 scripts inherit container defaults;
# on the host we set explicitly so commits have a clean author).
git -C "$REPO_PATH" config user.email "vps-backup@openclaw.local"
git -C "$REPO_PATH" config user.name  "openclaw-vps-backup"

# --- Stage HOST glue: /host/ ---
log "staging host/"
mkdir -p "$STAGE/host/usr-local-bin" "$STAGE/host/systemd"

# Custom CLIs in /usr/local/bin — keep only shell scripts, python scripts, and
# symlinks into /root/.openclaw/scripts/. Skip compiled binaries (upstream
# packages like gog, ollama, yt-dlp, caddy, npm CLIs).
USR_INCLUDED=0; USR_SKIPPED=0
for f in /usr/local/bin/*; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  if [ -L "$f" ]; then
    target=$(readlink -f "$f")
    case "$target" in
      /root/.openclaw/scripts/*)
        cp -a "$f" "$STAGE/host/usr-local-bin/$name"
        USR_INCLUDED=$((USR_INCLUDED+1))
        ;;
      *)
        USR_SKIPPED=$((USR_SKIPPED+1))
        ;;
    esac
  elif [ -f "$f" ]; then
    desc=$(file -b "$f")
    case "$desc" in
      *"Bourne-Again shell script"*|*"POSIX shell script"*|*"Python script"*|*"ASCII text"*)
        cp -a "$f" "$STAGE/host/usr-local-bin/$name"
        USR_INCLUDED=$((USR_INCLUDED+1))
        ;;
      *)
        USR_SKIPPED=$((USR_SKIPPED+1))
        ;;
    esac
  fi
done
log "host/usr-local-bin: included=$USR_INCLUDED, skipped=$USR_SKIPPED (binaries)"

# crontab.txt — root's crontab
if crontab -l > "$STAGE/host/crontab.txt" 2>>"$LOG"; then
  CRON_LINES=$(wc -l < "$STAGE/host/crontab.txt")
  log "host/crontab.txt: $CRON_LINES lines"
else
  log "WARNING: crontab -l failed; writing empty file"
  : > "$STAGE/host/crontab.txt"
fi

# systemd units — openclaw-* only
SYSD_COUNT=0
rm -f "$STAGE/host/systemd/"*.service 2>/dev/null
for f in /etc/systemd/system/openclaw-*.service; do
  [ -f "$f" ] || continue
  cp -a "$f" "$STAGE/host/systemd/$(basename "$f")"
  SYSD_COUNT=$((SYSD_COUNT+1))
done
log "host/systemd: $SYSD_COUNT units"

# --- Stage CONFIG: /config/ ---
log "staging config/"
mkdir -p "$STAGE/config"

# Gateway routing config — SANITIZED. /root/.openclaw/openclaw.json has
# inline provider API keys (Google AIza... at minimum, confirmed 2026-05-29
# via chart issue-openclaw-json-embedded-google-keys-20260529). Walk the
# JSON and replace any "apiKey", "api_key", "token", "secret", "password",
# "client_secret", "refresh_token", "access_token" string values with
# "<REDACTED>" before staging. Structure is preserved; values are not.
if [ -f /root/.openclaw/openclaw.json ]; then
  python3 -c "
import json
SENSITIVE = {'apiKey','api_key','token','secret','password',
             'client_secret','refresh_token','access_token',
             'botToken','bot_token','authToken','auth_token'}
def scrub(o):
    if isinstance(o, dict):
        return {k: ('<REDACTED>' if (k in SENSITIVE and isinstance(v, str) and v) else scrub(v))
                for k, v in o.items()}
    if isinstance(o, list):
        return [scrub(v) for v in o]
    return o
with open('/root/.openclaw/openclaw.json') as f:
    cfg = json.load(f)
with open('$STAGE/config/openclaw.json','w') as f:
    json.dump(scrub(cfg), f, indent=2)
" 2>>"$LOG" || log "WARNING: openclaw.json sanitization failed"
fi

# Claude Code host settings — sanitize MCP server credentials if any are embedded.
# We strip the .mcpServers field entirely (their auth lives inline), keep the
# rest. The allowlist + statusLine are what makes this useful at restore.
if [ -f /root/.claude/settings.json ]; then
  python3 -c "
import json
with open('/root/.claude/settings.json') as f:
    cfg = json.load(f)
# Drop fields that could carry secrets at the top level
cfg.pop('mcpServers', None)
with open('$STAGE/config/claude-settings.json','w') as f:
    json.dump(cfg, f, indent=2)
" 2>>"$LOG" || log "WARNING: could not sanitize claude settings.json"
fi

# Claude Code operational context
[ -f /root/.claude/CLAUDE.md ] && \
  cp -a /root/.claude/CLAUDE.md "$STAGE/config/claude-CLAUDE.md"

# OpenClaw runtime config
for f in /root/.openclaw/config/disabled-plugins.json \
         /root/.openclaw/config/error-patterns.json \
         /root/.openclaw/config/test-baselines.json; do
  [ -f "$f" ] && cp -a "$f" "$STAGE/config/$(basename "$f")"
done

# .env.template — variable names only, never values.
# Mirrors env-backup.sh logic but reads /root/openclaw/.env (host path).
if [ -f /root/openclaw/.env ]; then
  grep -E '^[A-Z_][A-Z0-9_]*=.' /root/openclaw/.env 2>/dev/null \
    | sed 's/=.*/=/' \
    | sort -u \
    > "$STAGE/config/.env.template"
  ENV_KEYS=$(wc -l < "$STAGE/config/.env.template")
  log "config/.env.template: $ENV_KEYS keys"
fi

# --- Stage STATE: /state/ ---
log "staging state/"
mkdir -p "$STAGE/state/memory" "$STAGE/state/ddl"

# MEMORY.md + topic files (markdown only, no binary)
if [ -d /root/.claude/projects/-root/memory ]; then
  cp -a /root/.claude/projects/-root/memory/MEMORY.md "$STAGE/state/MEMORY.md" 2>/dev/null || true
  rm -f "$STAGE/state/memory/"*.md 2>/dev/null
  for f in /root/.claude/projects/-root/memory/*.md; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "MEMORY.md" ] && continue
    cp -a "$f" "$STAGE/state/memory/$(basename "$f")"
  done
fi

# Reactor journal head + DECISIONS
[ -f /root/.openclaw/reactor-journal.md ] && \
  cp -a /root/.openclaw/reactor-journal.md "$STAGE/state/reactor-journal.md"
[ -f /root/.openclaw/DECISIONS.md ] && \
  cp -a /root/.openclaw/DECISIONS.md "$STAGE/state/DECISIONS.md"

# SQLite DDL dumps — schema only, never data
for db in /root/.openclaw/ops.db \
          /root/.openclaw/charts.db \
          /root/.openclaw/transcripts.db \
          /root/.openclaw/scope.db; do
  [ -f "$db" ] || continue
  name=$(basename "$db")
  sqlite3 "$db" .schema > "$STAGE/state/ddl/${name}.schema.sql" 2>>"$LOG" || \
    log "WARNING: schema dump failed for $db"
done

# --- Stage README + RESTORE + .gitignore ---
# README is regenerated each run with current timestamp + stats
cat > "$STAGE/README.md" <<EOF
# openclaw-vps

Rebuild-the-VPS backup for Robert Supernor's OpenClaw VPS. Auto-pushed nightly
at 03:30 UTC by \`/root/.openclaw/scripts/vps-backup.sh\` via
\`backup-suite.sh\`. **No secrets are ever pushed here** — a pre-push grep
guard at \`vps-backup-secrets-guard.sh\` blocks any commit that contains a
known secret pattern.

## What's in here

| Path | What |
|---|---|
| \`host/usr-local-bin/\` | Custom CLIs from /usr/local/bin (chart, oc, backbone, …) |
| \`host/crontab.txt\` | root crontab snapshot |
| \`host/systemd/\` | Custom systemd units (openclaw-*) |
| \`config/openclaw.json\` | Gateway routing config |
| \`config/claude-settings.json\` | Claude Code allowlist (mcpServers stripped) |
| \`config/claude-CLAUDE.md\` | Claude Code operational context |
| \`config/.env.template\` | Env-var names only, no values |
| \`state/MEMORY.md\`, \`state/memory/\` | Claude's persistent memory |
| \`state/reactor-journal.md\` | Reactor journal head |
| \`state/DECISIONS.md\` | Decisions digest |
| \`state/ddl/\` | SQLite schema dumps (DDL only, no data) |
| \`RESTORE.md\` | Step-by-step rebuild walkthrough |

Last push: this commit. See \`RESTORE.md\` to rebuild from scratch.
EOF

# RESTORE.md ships from /tmp/RESTORE.md the first time, then is left alone.
# (We re-copy it each push so updates to the canonical file propagate.)
if [ -f /tmp/RESTORE.md ]; then
  cp /tmp/RESTORE.md "$STAGE/RESTORE.md"
fi

# .gitignore — defense-in-depth alongside the guard
cat > "$STAGE/.gitignore" <<'EOF'
# Defense-in-depth: the secrets-guard already blocks these, but a tracked
# .gitignore prevents accidental staging if someone runs git add manually.
*.env
.env
.env.local
*.credentials.json
*auth.json
*access_token*
*refresh_token*
*.pem
*.key
id_rsa*
.ssh/
credentials/
EOF

# --- Secrets guard pre-push ---
log "running secrets guard"
if ! bash "$GUARD" "$STAGE" >> "$LOG" 2>&1; then
  echo "0" > "$EXIT_LOG"   # script ran cleanly but refused to push
  log "secrets guard FAILED — aborting push (no commit made)"
  echo '{"status":"BLOCKED","message":"secrets guard found patterns; refusing to push. See log.","pushed":false}'
  exit 1
fi

# --- Commit and push ---
cd "$REPO_PATH"
git add -A
if git diff --cached --quiet; then
  log "no changes since last push"
  echo "0" > "$EXIT_LOG"
  echo "{\"status\":\"PASS\",\"message\":\"No changes\",\"pushed\":false,\"usr_local_bin\":$USR_INCLUDED,\"systemd\":$SYSD_COUNT}"
  exit 0
fi

CHANGED=$(git diff --cached --stat | tail -1)
git commit -m "[vps-backup] $(ts) auto-backup" -q

# Push: detect first-push (no upstream yet) vs subsequent
if git push --quiet origin main 2>>"$LOG"; then
  SHA=$(git rev-parse --short HEAD)
  log "push OK sha=$SHA"
  echo "0" > "$EXIT_LOG"
  echo "{\"status\":\"PASS\",\"message\":\"vps-backup pushed\",\"pushed\":true,\"sha\":\"$SHA\",\"usr_local_bin\":$USR_INCLUDED,\"systemd\":$SYSD_COUNT,\"changes\":\"$CHANGED\"}"
elif git push --quiet -u origin main 2>>"$LOG"; then
  SHA=$(git rev-parse --short HEAD)
  log "first push OK sha=$SHA"
  echo "0" > "$EXIT_LOG"
  echo "{\"status\":\"PASS\",\"message\":\"vps-backup first push\",\"pushed\":true,\"sha\":\"$SHA\",\"usr_local_bin\":$USR_INCLUDED,\"systemd\":$SYSD_COUNT,\"changes\":\"$CHANGED\"}"
else
  log "push FAILED"
  echo "1" > "$EXIT_LOG"
  die "git push failed; see $LOG"
fi
