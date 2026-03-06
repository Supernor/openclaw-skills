#!/bin/bash
# qmd-setup.sh — Run after `docker compose build` to install QMD + dependencies.
# Installs bun globally, qmd via bun, fixes permissions, and runs initial embed.
# Safe to re-run (idempotent).
#
# Usage: bash /root/.openclaw/scripts/qmd-setup.sh
# Rollback: Remove memory.backend from openclaw.json, restart gateway.
set -euo pipefail
cd /root/openclaw

echo "=== QMD Post-Build Setup ==="

# 1. Fix npm cache ownership (prevents EACCES on node-llama-cpp builds)
echo "[1/7] Fixing npm cache ownership..."
docker compose exec --user root openclaw-gateway sh -c \
  'mkdir -p /home/node/.npm && chown -R node:node /home/node/.npm'

# 2. Install cmake + build-essential (needed by node-llama-cpp for embedding model)
echo "[2/7] Installing cmake + build-essential..."
docker compose exec --user root openclaw-gateway sh -c \
  'if ! command -v cmake >/dev/null 2>&1; then
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends cmake build-essential && apt-get clean && rm -rf /var/lib/apt/lists/*
  else
    echo "cmake already installed"
  fi'

# 3. Install bun globally at /usr/local/bin
echo "[3/7] Installing bun at /usr/local/bin..."
docker compose exec --user root openclaw-gateway sh -c \
  'if [ ! -f /usr/local/bin/bun ]; then
    curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash
  else
    echo "bun already at /usr/local/bin/bun"
  fi'

# 4. Install qmd via bun + create wrapper (use docker cp to avoid shebang escaping)
echo "[4/7] Installing qmd via bun..."
docker compose exec --user root openclaw-gateway sh -c \
  'export PATH="/usr/local/bin:$PATH" && bun install -g @tobilu/qmd@latest 2>&1 | tail -3 && chown -R node:node /home/node/.bun /home/node/.cache 2>/dev/null'

# Write wrapper via docker cp (avoids shell shebang escaping issues)
QMD_PKG_PATH="/home/node/.bun/install/global/node_modules/@tobilu/qmd/qmd"
WRAPPER=$(mktemp)
cat > "$WRAPPER" << 'WRAPPER_EOF'
#!/bin/bash
exec /home/node/.bun/install/global/node_modules/@tobilu/qmd/qmd "$@"
WRAPPER_EOF
CONTAINER_ID=$(docker compose ps -q openclaw-gateway)
docker cp "$WRAPPER" "$CONTAINER_ID":/usr/local/bin/qmd
docker compose exec --user root openclaw-gateway chmod 755 /usr/local/bin/qmd
rm -f "$WRAPPER"
echo "qmd wrapper installed"

# 5. Fix memory-lancedb plugin (openai module, known issue)
echo "[5/7] Fixing memory-lancedb openai dependency..."
docker compose exec --user root openclaw-gateway sh -c \
  'cd /app/extensions/memory-lancedb && node -e "require(\"openai\")" 2>/dev/null || npm install openai 2>&1 | tail -2'

# 6. Add workspace collection + run embed (downloads ~330MB model on first run)
echo "[6/7] Adding collection + running embed..."
docker compose exec openclaw-gateway sh -c \
  'qmd collection list 2>/dev/null | grep -q workspace || qmd collection add /home/node/.openclaw/workspace --name workspace --pattern "**/*.md"'
docker compose exec openclaw-gateway qmd embed

# 7. Restart gateway to pick up lancedb fix
echo "[7/7] Restarting gateway..."
docker compose restart openclaw-gateway
sleep 12

echo ""
echo "=== QMD Setup Complete ==="
echo "Verify: docker compose exec openclaw-gateway qmd status"
echo "Test:   docker compose exec openclaw-gateway openclaw memory search --query 'test'"
