#!/bin/bash
# gh-token-refresh.sh — keep the STATIC .env GH_TOKEN in sync with the LIVE gh
# token (dynamic single source of truth = gh's stored login).
#
# WHY: Docker `env_file` loads .env into the gateway container at start, so that
# copy is unavoidably static. This refresher makes it self-heal: whenever the
# live gh token differs from .env, it rewrites .env (names/values untouched
# except GH_TOKEN) so the container gets a fresh token on its next restart and
# the host-side .env fallback never goes stale. Host scripts themselves already
# resolve live via `gh-token`; this only closes the static-copy gap.
# Pairs with /usr/local/bin/gh-token. Chart: fix-github-token-dynamic-20260624.
set -eo pipefail
ENV=/root/openclaw/.env
LOG=/root/.openclaw/logs/gh-token-refresh.log

live=$(env -u GH_TOKEN -u GITHUB_TOKEN gh auth token 2>/dev/null || true)
if [ -z "$live" ]; then
  echo "$(date -u +%FT%TZ) gh-token-refresh: gh has no token (not logged in?) — left .env unchanged" >> "$LOG"
  exit 0
fi
cur=$(grep '^GH_TOKEN=' "$ENV" 2>/dev/null | cut -d= -f2- || true)
if [ "$live" = "$cur" ]; then
  echo "$(date -u +%FT%TZ) gh-token-refresh: .env already current (no change)" >> "$LOG"
  exit 0
fi
cp -a "$ENV" "$ENV.bak-ghtoken-refresh-$(date -u +%Y%m%d-%H%M%S)"
python3 - "$live" "$ENV" <<'PY'
import sys
tok, env = sys.argv[1], sys.argv[2]
lines = open(env).read().splitlines(); out = []; found = False
for l in lines:
    if l.startswith("GH_TOKEN="):
        out.append("GH_TOKEN=" + tok); found = True
    else:
        out.append(l)
if not found:
    out.append("GH_TOKEN=" + tok)
open(env, "w").write("\n".join(out) + "\n")
PY
echo "$(date -u +%FT%TZ) gh-token-refresh: .env GH_TOKEN updated to live gh token (was stale)" >> "$LOG"
