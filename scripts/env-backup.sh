#!/bin/bash
# env-backup.sh — Generate .env.template (names only) and push to openclaw-config
# Outputs structured JSON. Zero LLM tokens needed.
set -euo pipefail

# NOTE: /app/.env only has infra keys. Provider keys are in the host .env
# which docker-compose passes as env vars. We combine both sources.
ENV_FILE="${1:-/app/.env}"
REPO_PATH="/home/node/.openclaw/repos/openclaw-config"

if [ ! -f "$ENV_FILE" ]; then
  echo '{"status":"ERROR","message":"env file not found"}'
  exit 1
fi

# Generate template from .env file (key names only, NEVER values)
FILE_TEMPLATE=$(grep -E '^[A-Z_]+=.' "$ENV_FILE" | sed 's/=.*/=/' | sort)
# Also include provider keys that are injected via docker-compose env vars
PROVIDER_KEYS="OPENCLAW_PROD_ANTHROPIC_KEY OPENCLAW_PROD_DISCORD_TOKEN OPENCLAW_PROD_GOOGLE_AI_KEY OPENCLAW_PROD_OPENROUTER_KEY OPENCLAW_PROD_SAG_KEY OPENCLAW_PROD_DISCORD_APP_ID"
ENV_TEMPLATE=""
for key in $PROVIDER_KEYS; do
  if [ -n "${!key+x}" ]; then
    ENV_TEMPLATE="${ENV_TEMPLATE}${key}=\n"
  fi
done
TEMPLATE=$(echo -e "${FILE_TEMPLATE}\n${ENV_TEMPLATE}" | sort -u | grep -v '^$')

# SAFETY: verify no values leaked
LEAKED=$(echo "$TEMPLATE" | grep -E '^[A-Z_]+=.+' || true)
if [ -n "$LEAKED" ]; then
  echo '{"status":"FATAL","message":"Value found in template — aborting","leaked_count":'$(echo "$LEAKED" | wc -l)'}'
  exit 2
fi

KEY_COUNT=$(echo "$TEMPLATE" | grep -c '^[A-Z]' || echo 0)

# Ensure repo clone exists
if [ ! -d "$REPO_PATH/.git" ]; then
  git clone https://github.com/Supernor/openclaw-config.git "$REPO_PATH" 2>/dev/null
fi

# Write template
echo "$TEMPLATE" > "$REPO_PATH/.env.template"

# Commit and push
cd "$REPO_PATH"
git add .env.template
if git diff --cached --quiet; then
  echo '{"status":"PASS","message":"No changes","key_count":'"$KEY_COUNT"',"pushed":false}'
else
  git commit -m "[env-backup] $(date -u +%Y-%m-%dT%H:%M:%SZ) update .env.template" -q
  if git push origin main -q 2>/dev/null; then
    echo '{"status":"PASS","message":"Template updated and pushed","key_count":'"$KEY_COUNT"',"pushed":true,"sha":"'"$(git rev-parse --short HEAD)"'"}'
  else
    echo '{"status":"ERROR","message":"Commit succeeded but push failed","key_count":'"$KEY_COUNT"',"pushed":false}'
    exit 1
  fi
fi
