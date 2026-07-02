#!/usr/bin/env bash
# vps-backup-secrets-guard.sh
# Scans a directory tree for secret patterns. Exits non-zero on ANY hit.
# Called by vps-backup.sh before `git add`. If this returns non-zero, NO push.
# Mirrors the safety check in env-backup.sh:28-33 but for arbitrary content.

set -eo pipefail

TARGET="${1:?Usage: vps-backup-secrets-guard.sh <dir-to-scan>}"

if [ ! -d "$TARGET" ]; then
  echo "FATAL: target $TARGET is not a directory" >&2
  exit 2
fi

# Pattern catalog — extended-regex, case-sensitive. Order matters only for
# the first-match reporting. Keep this list narrow: false positives in a
# nightly cron are noisy. Add patterns when a NEW class of secret enters
# the system, not when one specific value appears.
#
# DESIGN NOTE: the `*_KEY=`/`*_TOKEN=` env-style patterns require
# start-of-line (^) so they don't match string-literal checks like
# `line.startswith("FOO_KEY=")` inside source code. Real secrets in .env
# files always sit at column 1.
PATTERNS=(
  'BEGIN [A-Z ]*PRIVATE KEY'                       # SSH/PGP/x509 private keys
  '^OPENCLAW_PROD_[A-Z_]+=[^[:space:]]'            # provider keys with VALUE at SOL
  '^ANTHROPIC_API_KEY=[^[:space:]]'
  '^OPENAI_API_KEY=[^[:space:]]'
  '^GOOGLE_AI_KEY=[^[:space:]]'
  '^DISCORD_TOKEN=[^[:space:]]'
  '^DISCORD_BOT_TOKEN=[^[:space:]]'
  '^TELEGRAM_BOT_TOKEN=[^[:space:]]'
  '"client_secret"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_~.-]+"'
  '"refresh_token"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_~.-]+"'
  'ghp_[A-Za-z0-9]{30,}'            # GitHub PATs
  'ghs_[A-Za-z0-9]{30,}'            # GitHub App tokens
  'sk-ant-[A-Za-z0-9_-]{20,}'       # Anthropic API key shape ({20,}: real keys are 90+ chars; unbounded '+' false-positived on the prose string 'sk-ant-oat' in a memory .md — 2026-07-01)
  'sk-proj-[A-Za-z0-9_-]{20,}'      # OpenAI project key shape (bounded to avoid prose false-positives, same as sk-ant)
  'AIza[A-Za-z0-9_-]{30,}'          # Google API key shape
  'xoxb-[A-Za-z0-9-]{20,}'          # Slack bot token shape (bounded to avoid prose false-positives)
)

HITS=()
for pat in "${PATTERNS[@]}"; do
  # grep -REn: extended regex, recursive, line numbers
  # --exclude-dir=.git: don't scan git internals (PAT in .git/config is local)
  # Quote the pattern carefully so shell doesn't glob.
  out=$(grep -REn --binary-files=without-match --exclude-dir=.git "$pat" "$TARGET" 2>/dev/null || true)
  if [ -n "$out" ]; then
    HITS+=("=== pattern: $pat ===")
    HITS+=("$(echo "$out" | head -3)")
  fi
done

if [ ${#HITS[@]} -gt 0 ]; then
  echo "SECRETS GUARD: FAIL — refusing to allow these files into the openclaw-vps repo" >&2
  printf '%s\n' "${HITS[@]}" >&2
  echo "" >&2
  echo "Resolution: remove the offending file from the staging dir, or add the" >&2
  echo "specific path to the script's exclude list if it's a known false positive." >&2
  exit 1
fi

echo "SECRETS GUARD: PASS — no secret patterns found in $TARGET"
exit 0
