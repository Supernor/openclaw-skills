#!/usr/bin/env bash
# daily-diary.sh — Generate and post the daily diary.
# Intent: Informed, Coherent.
# Cron: 0 23 * * * /root/.openclaw/scripts/daily-diary.sh
#
# Usage:
#   daily-diary.sh                       # today's diary (cron path)
#   daily-diary.sh 2026-05-26            # backfill that day
#   daily-diary.sh --dry-run             # print today's prompt only
#   daily-diary.sh --dry-run 2026-05-26  # print that day's prompt
#
# Architecture (rewritten 2026-05-28, see chart procedure-daily-diary-pipeline-20260528):
#   Primary  : host claude CLI invoked DIRECTLY (Max plan OAuth, flat-rate).
#              Bypasses claude-code-run host_op because that handler forces
#              metered ANTHROPIC_API_KEY (zero credit balance). See chart
#              issue-claude-code-run-handler-blocks-seat-auth-20260528.
#              Host claude does NOT have openclaw-gateway MCP wired, so
#              context (charts, ops.db, journal) is pre-gathered shell-side
#              and passed inline.
#   Fallback : oc agent --agent spec-historian via gateway (the old path),
#              which DOES have MCP and uses send_message tool to post itself.
#   Discord  : primary path posts via host-side curl with OPENCLAW_PROD_DISCORD_TOKEN
#              from /root/openclaw/.env (mirrors stability-monitor.sh telegram_direct
#              pattern). Fallback path posts via Historian's send_message tool.

set -eo pipefail

# cron PATH lacks ~/.local/bin (claude CLI lives there)
export PATH="/root/.local/bin:$PATH"
# --- Config ---
COMPOSE_DIR="/root/openclaw"
LOG_DIR="/root/.openclaw/logs"
LOG="$LOG_DIR/daily-diary.log"
OC="/usr/local/bin/oc"
AGENT="spec-historian"
TIMEOUT=300
DISCORD_CHANNEL_ID="1480026250645868654"   # #daily-diary

# --- Arg parse (date arg + --dry-run, order-insensitive) ---
DRY_RUN=false
DATE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      DATE="$arg"
      ;;
    *)
      echo "Unknown arg: $arg" >&2
      echo "Usage: daily-diary.sh [YYYY-MM-DD] [--dry-run]" >&2
      exit 2
      ;;
  esac
done
DATE="${DATE:-$(date -u +%Y-%m-%d)}"
TODAY=$(date -u +%Y-%m-%d)
if [[ "$DATE" > "$TODAY" ]]; then
  echo "Refusing to generate diary for future date: $DATE" >&2
  exit 2
fi
IS_BACKFILL="no"
[ "$DATE" != "$TODAY" ] && IS_BACKFILL="yes"

# --- Environment ---
export GOG_KEYRING_PASSWORD="openclaw-comms-keyring"
export PATH="/usr/local/bin:$PATH"
mkdir -p "$LOG_DIR"
mkdir -p /root/.openclaw/health

# Discord bot token (from .env, mirrors stability-monitor pattern)
source /root/openclaw/.env 2>/dev/null || true
DISCORD_TOKEN="${OPENCLAW_PROD_DISCORD_TOKEN:-}"

# --- Helpers ---
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "[$(ts)] $*" >> "$LOG"; }
die() { log "FATAL: $*"; echo "[$(ts)] FATAL: $*" >&2; exit 1; }

health_emit() {
  local status="$1" path="$2"
  echo "{\"ts\":\"$(ts)\",\"source\":\"daily-diary\",\"status\":\"$status\",\"date\":\"$DATE\",\"path\":\"$path\"}" \
    >> /root/.openclaw/health/buffer.jsonl 2>/dev/null || true
}

# --- Content validation (added 2026-07-01, task #3756) ---
# A length check alone let meta/refusal text ("I don't have shell access...",
# "I'll append a brief journal note...") pass as a real diary and get posted +
# marked ok (Jun 29 & Jun 30, 2026). validate_diary rejects anything that is not
# an actual diary. Returns 0 = valid diary, 1 = reject (caller must NOT post it).
# $1 = candidate diary text. Logs the specific reason on rejection.
validate_diary() {
  local text="$1"
  local low
  low=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')

  # 1) Canonical header: must contain "Daily Diary" AND the target date.
  if ! printf '%s' "$low" | grep -q "daily diary"; then
    log "REJECT: missing 'Daily Diary' header"
    return 1
  fi
  if ! printf '%s' "$text" | grep -qF "$DATE"; then
    log "REJECT: header missing target date $DATE"
    return 1
  fi

  # 2) At least one required diary section header must be present.
  #    (labels are stable even if the leading emoji is dropped)
  if ! printf '%s' "$text" | grep -qiE 'WINS|LOSSES|SIDE WINS|DISCOVERIES|WHAT MAKES SENSE|FAMILY NOTES'; then
    log "REJECT: no diary section headers (WINS/LOSSES/DISCOVERIES/...)"
    return 1
  fi

  # 3) Reject tool/access/meta responses even if they somehow echo the header.
  local bad='shell access|file access|do not have access|dont have access|don.t have access|i do not have|i don.t have|i cannot|i can.t|i.m unable|i am unable|ready to post|run this (on|in) (the )?host|run it on the host|paste this|i.ll (append|add|run|post|write)|i will (append|add|run|post|write)|let me know if|as an ai|doctor warnings|config warnings|no shell'
  if printf '%s' "$low" | grep -qiE "$bad"; then
    local hit
    hit=$(printf '%s' "$low" | grep -oiE "$bad" | head -1)
    log "REJECT: meta/access/tool phrase detected ('$hit')"
    return 1
  fi

  # 4) Reject content that is only code fences / whitespace once markers stripped.
  local stripped
  stripped=$(printf '%s' "$text" | sed -E 's/```[a-zA-Z]*//g' | tr -d '[:space:]`')
  if [ ${#stripped} -lt 120 ]; then
    log "REJECT: effectively empty after stripping fences/whitespace (${#stripped} chars)"
    return 1
  fi

  return 0
}

# --- Preflight ---
command -v "$OC" >/dev/null 2>&1 || die "oc CLI not found at $OC"
command -v claude >/dev/null 2>&1 || die "claude CLI not found (host Max plan)"
command -v jq >/dev/null 2>&1 || die "jq not found"
[ -n "$DISCORD_TOKEN" ] || die "OPENCLAW_PROD_DISCORD_TOKEN missing from $COMPOSE_DIR/.env"
[ -f /root/.claude/.credentials.json ] || log "WARNING: /root/.claude/.credentials.json missing — claude CLI may fall back to API key"

# Gateway is only required for the Historian FALLBACK. Primary works without it.
GATEWAY_UP=false
if docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps --status running 2>/dev/null | grep -q openclaw-gateway; then
  GATEWAY_UP=true
fi
[ "$GATEWAY_UP" = false ] && log "WARNING: openclaw-gateway not running — Historian fallback unavailable"

# --- Context gathering (shell-side, deterministic) ---
gather_context() {
  echo "=== CHART SEARCH for $DATE ==="
  /usr/local/bin/chart search "$DATE" 2>/dev/null | head -80 || true
  echo
  echo "=== OPS.DB TASKS on $DATE ==="
  sqlite3 /root/.openclaw/ops.db \
    "SELECT created_at, agent, status, substr(task,1,120), substr(outcome,1,200)
     FROM tasks WHERE date(created_at)='$DATE' ORDER BY created_at LIMIT 50;" 2>/dev/null || true
  echo
  echo "=== ENGINE USAGE on $DATE ==="
  sqlite3 /root/.openclaw/ops.db \
    "SELECT engine, COUNT(*) calls, SUM(success) ok, SUM(CASE WHEN success=0 THEN 1 ELSE 0 END) failed
     FROM engine_usage WHERE date(ts)='$DATE' GROUP BY engine;" 2>/dev/null || true
  echo
  echo "=== REACTOR JOURNAL entries for $DATE ==="
  awk -v date="$DATE" '
    /^# Reactor Session — / { in_section = ($0 ~ date) ? 1 : 0 }
    in_section { print }
  ' /root/.openclaw/reactor-journal.md 2>/dev/null | head -250 || true
}

CONTEXT=$(gather_context)

# --- Build prompt ---
BACKFILL_NOTE=""
if [ "$IS_BACKFILL" = "yes" ]; then
  BACKFILL_NOTE="

BACKFILL MODE: This diary is for $DATE but is being written on $(date -u +%Y-%m-%d). Format the header line as:
📜 Daily Diary - $DATE *(backfill — written $(date -u +%Y-%m-%d))*
so the Discord post is unambiguous in the channel."
fi

PROMPT="You are Historian, the OpenClaw fleet's chronicler. Write the daily diary for ${DATE} in the standard two-part format. Robert reads it in Discord #daily-diary every night.

Voice: yours — narrative inside the bullets, observational, dry humor where it lands. Ground every claim in the context below; do not invent events.

OUTPUT FORMAT (REQUIRED) — exactly these section headers, in this order, with one blank line between sections. Use bullets (dash + space) under each header. Skip a section ONLY if the context has nothing for it (e.g. no family context found):

📜 Daily Diary - ${DATE}

🏆 WINS
- ...

💔 LOSSES
- ...

🎯 SIDE WINS
- ...

---SPLIT---

🔍 DISCOVERIES
- ...

💡 WHAT MAKES SENSE
- ...

👨‍👩‍👦 FAMILY NOTES
- ...

RULES:
- The literal line '---SPLIT---' on its own line separates the two Discord messages. Each half must be under 1900 chars.
- Each bullet is one short narrative sentence, not a label. Aim 3-6 bullets per section.
- No outer code fences. No JSON. No 'Summary' or 'Conclusion'. No sign-off.
- Do not call any tools.${BACKFILL_NOTE}

--- CONTEXT FOR ${DATE} ---
${CONTEXT}
--- END CONTEXT ---"

# --- Dry-run early exit ---
if [ "$DRY_RUN" = true ]; then
  echo "=== DRY RUN for $DATE (backfill=$IS_BACKFILL) ==="
  echo "Primary  : claude CLI (Max plan OAuth, flat-rate)"
  echo "Fallback : oc agent --agent $AGENT (gateway up=$GATEWAY_UP)"
  echo "Discord  : channel $DISCORD_CHANNEL_ID via OPENCLAW_PROD_DISCORD_TOKEN"
  echo "Timeout  : ${TIMEOUT}s"
  echo "Prompt   : ${#PROMPT} chars, context=${#CONTEXT} chars"
  echo
  echo "$PROMPT"
  exit 0
fi

# --- Discord direct-post: single message (host-side, no gateway dependency) ---
discord_post_one() {
  local content="$1"
  # Discord enforces 2000-char content limit per message; truncate if needed
  if [ ${#content} -gt 1980 ]; then
    content="${content:0:1975}… [truncated]"
  fi
  local payload
  payload=$(jq -n --arg c "$content" '{content: $c}')
  local http_code
  http_code=$(curl -s -o /tmp/diary-discord-resp.$$ -w '%{http_code}' \
    -X POST "https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages" \
    -H "Authorization: Bot ${DISCORD_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload")
  log "Discord POST -> HTTP $http_code (${#content} chars)"
  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    rm -f /tmp/diary-discord-resp.$$
    return 0
  fi
  log "Discord error body: $(head -c 300 /tmp/diary-discord-resp.$$)"
  rm -f /tmp/diary-discord-resp.$$
  return 1
}

# --- Discord post: splits on ---SPLIT--- marker and posts one or two messages
#     in order. All-or-nothing: returns 0 only if every chunk posts.
#     TODO: handles a SINGLE marker. If claude ever emits >=2 markers, the
#     second-and-later get lumped into part2. Low likelihood given the prompt
#     instructs exactly one marker; will iterate on a foreach split if seen. ---
discord_post() {
  local content="$1"
  local marker="---SPLIT---"
  # Normalize: strip any stray code fences claude might add around the diary
  content=$(printf '%s' "$content" | sed -E 's/^[[:space:]]*```[a-zA-Z]*[[:space:]]*$//' | sed -E 's/^[[:space:]]*```[[:space:]]*$//')

  local part1 part2
  if [[ "$content" == *"$marker"* ]]; then
    part1="${content%%$marker*}"
    part2="${content#*$marker}"
    # Trim leading/trailing blank lines from each chunk
    part1=$(printf '%s' "$part1" | awk 'NF{p=1} p' | awk 'BEGIN{n=0} {a[n++]=$0} END{for(i=n-1;i>=0;i--) if(a[i]!="") {last=i; break} for(i=0;i<=last;i++) print a[i]}')
    part2=$(printf '%s' "$part2" | awk 'NF{p=1} p' | awk 'BEGIN{n=0} {a[n++]=$0} END{for(i=n-1;i>=0;i--) if(a[i]!="") {last=i; break} for(i=0;i<=last;i++) print a[i]}')
  else
    part1="$content"
    part2=""
  fi

  discord_post_one "$part1" || return 1
  if [ -n "$part2" ]; then
    # Tiny pause so Discord preserves order in fast back-to-back posts
    sleep 1
    discord_post_one "$part2" || return 1
  fi
  return 0
}

# --- Historian fallback (gateway path, uses send_message tool to post) ---
historian_fallback() {
  log "Falling back to $AGENT via oc agent"
  if [ "$GATEWAY_UP" != true ]; then
    log "Historian fallback skipped — gateway not running"
    return 1
  fi
  local hist_prompt
  hist_prompt="Generate the daily diary for ${DATE}. Steps:
1. Gather ${DATE} activity: query Chartroom (chart_search for the date), check agent session history, review reactor journal entries.
2. Write the diary in your standard format — what happened, key decisions, agent activity, anything noteworthy.
3. Post the finished diary to the Discord #daily-diary channel using the send_message tool (channel ID: ${DISCORD_CHANNEL_ID}).
If any step fails, still complete the remaining steps and note what failed."
  local out
  if out=$("$OC" agent --agent "$AGENT" --message "$hist_prompt" --timeout "$TIMEOUT" 2>&1 | grep -v "level=warning"); then
    # Transport success != work success: the agent can return an error payload or
    # near-empty text (seen 2026-06-11: "Agent couldn't generate a response" logged as complete).
    if printf '%s' "$out" | grep -qiE "couldn't generate a response|do(n.t| not) have (shell |file )?access|no shell access|i cannot generate|unable to generate" || [ "${#out}" -lt 200 ]; then
      log "Historian fallback FAILED (error marker or short output, ${#out} chars)"
      log "Historian output (first 500): ${out:0:500}"
      output-taint mark --agent "$AGENT" --reason "empty/error output"         --output "${out:0:500}" --source daily-diary 2>/dev/null || true
      return 1
    fi
    log "Historian fallback completed"
    log "Historian output (first 500): ${out:0:500}"
    echo "${out:0:500}" | output-taint auto --agent "$AGENT" --source daily-diary 2>/dev/null || true
    return 0
  else
    local rc=$?
    log "Historian fallback FAILED (exit $rc)"
    log "Historian output (first 500): ${out:0:500}"
    output-taint mark --agent "$AGENT" --reason "fallback failure" \
      --output "${out:0:500}" --source daily-diary 2>/dev/null || true
    return 1
  fi
}

# --- Primary path: host claude CLI ---
log "Daily diary triggered for $DATE (backfill=$IS_BACKFILL, primary=claude-cli, fallback=oc-agent-$AGENT)"
log "Context bundle: ${#CONTEXT} chars; prompt: ${#PROMPT} chars"

DIARY=""
PRIMARY_OK=false
CLAUDE_OUT=/tmp/diary-claude-$$.txt
# env -u ANTHROPIC_API_KEY: ensures claude uses Max plan OAuth, not metered API.
# +e around the timeout call so we capture exit code without aborting.
set +e
env -u ANTHROPIC_API_KEY timeout "$TIMEOUT" claude -p "$PROMPT" \
  --output-format text --tools none \
  > "$CLAUDE_OUT" 2>>"$LOG"
CLAUDE_RC=$?
set -e

if [ $CLAUDE_RC -eq 0 ] && [ -s "$CLAUDE_OUT" ]; then
  DIARY=$(cat "$CLAUDE_OUT")
  if [ ${#DIARY} -le 200 ]; then
    log "Primary (claude CLI) returned suspiciously short output (${#DIARY} chars) — treating as failure"
  elif ! validate_diary "$DIARY"; then
    log "Primary (claude CLI) output FAILED content validation (${#DIARY} chars) — treating as failure, first 200: ${DIARY:0:200}"
    output-taint mark --agent claude-cli --reason "invalid diary content" \
      --output "${DIARY:0:500}" --source daily-diary 2>/dev/null || true
  else
    PRIMARY_OK=true
    log "Primary (claude CLI) succeeded + validated (${#DIARY} chars)"
  fi
else
  log "Primary (claude CLI) failed (exit $CLAUDE_RC, output bytes=$(stat -c%s "$CLAUDE_OUT" 2>/dev/null || echo 0))"
fi
rm -f "$CLAUDE_OUT"

# --- Decision tree ---
if [ "$PRIMARY_OK" = true ]; then
  # Primary produced text — post via host-side Discord curl
  if discord_post "$DIARY"; then
    log "Diary posted (primary path)"
    health_emit ok primary
    log "Daily diary complete for $DATE"
    exit 0
  else
    # Discord post failed — try Historian for delivery (it uses gateway send_message)
    log "Discord direct post failed — attempting Historian fallback for delivery"
    if historian_fallback; then
      health_emit ok fallback-recovery
      exit 0
    else
      health_emit error all-paths-failed
      die "Both Discord direct post AND Historian fallback failed for $DATE"
    fi
  fi
else
  # Primary failed — Historian generates AND posts
  if historian_fallback; then
    health_emit ok fallback
    log "Daily diary complete for $DATE (via Historian fallback)"
    exit 0
  else
    health_emit error all-paths-failed
    die "Both claude primary AND Historian fallback failed for $DATE"
  fi
fi
