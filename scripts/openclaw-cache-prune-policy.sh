#!/usr/bin/env bash
# OpenClaw cache prune policy. Every deletion candidate is appended to the
# resilience board before removal, per Robert's 2026-10-05 directive.

set -uo pipefail

BOARD="/root/.openclaw/boards/resilience-program-20261005.md"
LOG="/root/.openclaw/logs/cache-prune-policy.log"
CLAUDE_VERSIONS="/root/.local/share/claude/versions"
PNPM_STORE="/root/.local/share/pnpm/store"
DRY_RUN=0

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
fi

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> "$LOG"
}

board_append() {
  local TEXT="$1"
  {
    echo
    echo "### Cache prune entry - $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "$TEXT"
  } >> "$BOARD"
}

bytes_for_path() {
  if [ -e "$1" ]; then
    du -sh "$1" 2>/dev/null | awk '{print $1}'
  else
    echo "missing"
  fi
}

build_process_active() {
  pgrep -af 'pnpm|npm|node-gyp|vite|webpack|esbuild|turbo|tsc' 2>/dev/null \
    | grep -v 'openclaw-cache-prune-policy.sh' \
    | grep -q .
}

run_pnpm_prune() {
  [ -d "$PNPM_STORE" ] || { log "pnpm store missing; skip"; return 0; }
  local before
  before=$(bytes_for_path "$PNPM_STORE")
  board_append "- Candidate listed before prune: \`$PNPM_STORE\` size ${before}. Action: pnpm store prune."
  if [ "$DRY_RUN" = "1" ]; then
    log "dry-run: would run pnpm store prune"
    return 0
  fi
  if build_process_active; then
    log "skip pnpm prune: package/build process active"
    return 0
  fi
  if command -v pnpm >/dev/null 2>&1; then
    pnpm store prune >> "$LOG" 2>&1 || log "pnpm store prune failed"
  elif command -v corepack >/dev/null 2>&1; then
    corepack pnpm store prune >> "$LOG" 2>&1 || log "corepack pnpm store prune failed"
  else
    log "pnpm/corepack not found; cannot prune pnpm store"
  fi
}

version_sort() {
  sort -V
}

run_claude_prune() {
  [ -d "$CLAUDE_VERSIONS" ] || { log "Claude versions dir missing; skip"; return 0; }
  local versions latest old path size
  versions=$(find "$CLAUDE_VERSIONS" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | version_sort)
  latest=$(echo "$versions" | sed '/^$/d' | tail -1)
  [ -n "$latest" ] || { log "no Claude version files found"; return 0; }

  echo "$versions" | sed '/^$/d' | while read -r old; do
    [ "$old" = "$latest" ] && continue
    path="$CLAUDE_VERSIONS/$old"
    size=$(bytes_for_path "$path")
    board_append "- Candidate listed before delete: \`$path\` size ${size}. Action: remove old Claude CLI version; keep latest \`$latest\`."
    if [ "$DRY_RUN" = "1" ]; then
      log "dry-run: would delete $path"
    else
      rm -f -- "$path"
      log "deleted old Claude CLI version $path"
    fi
  done
}

run_journal_vacuum() {
  board_append "- Candidate listed before vacuum: \`/var/log/journal\` size $(bytes_for_path /var/log/journal). Action: journalctl --vacuum-size=500M."
  if [ "$DRY_RUN" = "1" ]; then
    log "dry-run: would run journalctl --vacuum-size=500M"
  else
    journalctl --vacuum-size=500M >> "$LOG" 2>&1 || log "journalctl vacuum failed"
  fi
}

mkdir -p "$(dirname "$LOG")"
run_pnpm_prune
run_claude_prune
run_journal_vacuum
echo "RESULT_LABEL: ok"
log "cache prune policy completed dry_run=${DRY_RUN}"
