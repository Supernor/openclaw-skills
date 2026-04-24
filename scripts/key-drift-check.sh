#!/bin/bash
# key-drift-check.sh — Compare /app/.env keys against canonical list
# Outputs structured JSON. Zero LLM tokens needed.
set -euo pipefail

CANONICAL_KEYS=(
  GH_TOKEN
  OPENCLAW_GATEWAY_TOKEN
  OPENCLAW_PROD_ANTHROPIC_KEY
  OPENCLAW_PROD_DISCORD_TOKEN
  OPENCLAW_PROD_GOOGLE_AI_KEY
  OPENCLAW_PROD_OPENROUTER_KEY
  OPENAI_API_KEY
  TELEGRAM_BOT_TOKEN_ROBERT
  TELEGRAM_BOT_TOKEN_CORINNE
  TELEGRAM_BOT_TOKEN_SCRIBE
  TELEGRAM_BOT_TOKEN_TAP
  NVIDIA_NIM_API_KEY
  GEMINI_FREE_API_KEY
  OPENCLAW_GOOGLE_PRO_KEY
  CLOUDFLARE_API_TOKEN
)
# 15 canonical keys. Updated 2026-04-23 from actual /root/openclaw/.env contents.
# Why: nightly alert flagged false positive because canonical list was stale (only 7 keys).

EXCLUDED_KEYS=(
  OPENCLAW_PROD_DISCORD_APP_ID
  OPENCLAW_PROD_SAG_KEY
  OPENCLAW_IMAGE
  OPENCLAW_CONFIG_DIR
  OPENCLAW_WORKSPACE_DIR
  OPENCLAW_EXTENSIONS
  OPENCLAW_GATEWAY_PORT
  OPENCLAW_GATEWAY_BIND
  OPENCLAW_BRIDGE_PORT
  OPENCLAW_DOCKER_APT_PACKAGES
  CLOUDFLARE_ACCOUNT_ID
)
# Excluded: config values that aren't secrets (ports, paths, feature flags)

# Fixed: /app/.env doesn't exist inside the container. The real env file is on the host.
# Why: the gateway gets env vars via docker-compose environment config, not a file at /app/
ENV_FILE="${1:-/root/openclaw/.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo '{"status":"ERROR","message":"env file not found","file":"'"$ENV_FILE"'"}'
  exit 1
fi

# Extract actual key names from .env file (never values)
FILE_KEYS=$(grep -E '^[A-Z_]+=.' "$ENV_FILE" | cut -d= -f1 | sort)

# Also check runtime env vars (provider keys may be injected via docker-compose)
ENV_KEYS=""
for key in "${CANONICAL_KEYS[@]}"; do
  if [ -n "${!key+x}" ]; then
    ENV_KEYS="$ENV_KEYS"$'\n'"$key"
  fi
done

# Merge both sources
ACTUAL_KEYS=$(echo -e "$FILE_KEYS\n$ENV_KEYS" | sort -u | grep -v '^$')

MISSING=()
PRESENT=()
for key in "${CANONICAL_KEYS[@]}"; do
  if echo "$ACTUAL_KEYS" | grep -qx "$key"; then
    PRESENT+=("\"$key\"")
  else
    MISSING+=("\"$key\"")
  fi
done

# Find extra keys (not in canonical or excluded)
EXTRA=()
while IFS= read -r key; do
  is_canonical=false
  is_excluded=false
  for ck in "${CANONICAL_KEYS[@]}"; do [ "$key" = "$ck" ] && is_canonical=true; done
  for ek in "${EXCLUDED_KEYS[@]}"; do [ "$key" = "$ek" ] && is_excluded=true; done
  if ! $is_canonical && ! $is_excluded; then
    EXTRA+=("\"$key\"")
  fi
done <<< "$ACTUAL_KEYS"

TOTAL=${#CANONICAL_KEYS[@]}
FOUND=${#PRESENT[@]}

if [ ${#MISSING[@]} -eq 0 ]; then
  STATUS="PASS"
else
  STATUS="FAIL"
fi

# Output JSON
join_array() { local IFS=','; echo "$*"; }

cat << EOF
{
  "status": "$STATUS",
  "canonical": $TOTAL,
  "found": $FOUND,
  "missing": [$(join_array "${MISSING[@]+"${MISSING[@]}"}")],
  "extra": [$(join_array "${EXTRA[@]+"${EXTRA[@]}"}")],
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
