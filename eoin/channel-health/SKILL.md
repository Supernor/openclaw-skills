---
name: channel-health
description: Diagnose Discord and Telegram channel health — real status, not just what the monitor says
tags: [discord, telegram, channels, health, diagnosis, troubleshooting]
version: 1.0.0
---

# Channel Health Check

Diagnose the TRUE health of Discord and Telegram channels. This skill exists
because the system has multiple delivery paths per channel, and "down" alerts
can be misleading. Use this before telling Robert something is broken.

## Background you need to know

### Two Discord paths (independent of each other)
1. **Bot plugin** (via gateway) — handles DMs, slash commands, channel messages.
   Requires `@openclaw/discord` npm plugin installed AND loaded AND connected.
   Health check: `openclaw health` shows `Discord: configured`.
2. **Webhooks** (via reactor-post.sh) — handles ops channel updates.
   Works independently of the bot. Uses `/root/.openclaw/reactor-webhook-url.txt`.
   Robert sees these in #ops-reactor, #ops-nightly, etc.

**If Robert says "Discord is working" but health says "Discord is down":**
He's seeing webhook updates. The bot plugin may still be broken. Both paths
must be checked separately.

### Two Telegram paths (independent of each other)
1. **Gateway channel** — the main bot connection. Polls Telegram API.
   Health check: `openclaw health` shows `Telegram: configured`.
2. **telegram_direct()** — stability-monitor.sh calls Telegram API directly
   via curl, bypassing the gateway. Used for system alerts only.

**If you receive a Telegram alert saying "Telegram is down":**
Telegram API is fine (that's how the alert reached you). The GATEWAY'S
connection to Telegram had a hiccup. Check gateway logs, not Telegram API.

### Charts to read for deeper context
```
chart read issue-false-alert-loop-20260518     # The alert loop bug and fix
chart read issue-discord-channel-unavailable-20260518  # Discord 8-day outage
chart read procedure-discord-plugin-update     # Discord plugin version management
chart read learning-discord-externalized       # Why Discord needs special handling
chart read procedure-update-openclaw           # Update procedure (includes channel checks)
```

## Quick check (use this first)

Run the gateway health command and interpret the output:

```bash
# Step 1: Get health output
docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw health 2>&1 | grep -E "Telegram:|Discord:|Gateway"
```

### Interpreting results

| Output | Meaning | Action |
|--------|---------|--------|
| `Telegram: configured` | Gateway has Telegram connection | OK — Telegram is working |
| `Telegram: ok` | Same as configured | OK |
| No Telegram line | Gateway can't report Telegram status | Check gateway logs (see Deep Diagnosis) |
| `Discord: configured` | Discord bot is connected | OK — Discord bot is working |
| No Discord line | Discord plugin not loaded | See "Discord plugin not loaded" below |
| `Discord: degraded` | Bot connected but having issues | Check gateway logs for `[discord]` errors |
| `Gateway event loop: degraded` | Gateway under CPU pressure | Transient — causes intermittent empty health output |

## Deep diagnosis

### Discord plugin not loaded

This is the most common issue after OpenClaw updates. Discord was externalized
to an npm package in v2026.5.0. The plugin version must match the gateway.

```bash
# Step 1: Is the plugin installed?
docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw plugins list 2>&1 | grep discord

# Expected: a line showing @openclaw/discord with a version number
# If missing: plugin needs to be installed (see Fix below)

# Step 2: Is the plugin crashing?
docker compose -f /root/openclaw/docker-compose.yml logs --tail=50 openclaw-gateway 2>&1 | grep -E "\[discord\].*(exited|error|crash)"

# If you see "[discord] channel exited: Package subpath" — VERSION MISMATCH
# The plugin version is newer than the gateway and uses SDK features that don't exist yet.
# ERROR MEANING: "Package subpath './plugin-sdk/text-utility-runtime' is not defined"
#   = Plugin expects an SDK export the gateway doesn't have.
#   = Fix: install a plugin version that matches the gateway version.

# Step 3: What version is the gateway?
docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw --version 2>&1 | head -1

# Step 4: What Discord plugin versions exist?
docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway npm view @openclaw/discord versions --json 2>&1 | tail -10
```

### Fix: Install matching Discord plugin

**IMPORTANT VERSION RULE**: Plugin version must be <= gateway version.
If gateway is v2026.5.8, use @openclaw/discord@2026.5.7 (not 2026.5.12).

```bash
# Install plugin at version matching gateway (or closest lower version)
docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway \
  openclaw plugins install @openclaw/discord@VERSION --force

# Fix file permissions (plugin install modifies openclaw.json as root)
# ERROR IF SKIPPED: "EACCES: permission denied, open openclaw.json"
# MISLEADING SECONDARY ERROR: "gateway.mode is missing" (file can't be read, not actually missing)
chown 1000:1000 /root/.openclaw/openclaw.json

# Restart gateway to load the new plugin
docker compose -f /root/openclaw/docker-compose.yml restart openclaw-gateway

# Wait 30 seconds for startup, then verify
sleep 30
docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw health 2>&1 | grep "Discord:"
# Should show: Discord: configured
```

**Config is safe**: Plugin install does NOT touch your channel config, message
history, tokens, or channel mappings. It only installs code and updates the
plugin registry. Your Discord server setup, channels, and permissions are
preserved.

### Telegram not connecting

```bash
# Check gateway logs for Telegram errors
docker compose -f /root/openclaw/docker-compose.yml logs --tail=50 openclaw-gateway 2>&1 | grep -i telegram

# Common issues:
# "fetch timeout" — transient, usually resolves in next polling cycle
# "401 Unauthorized" — bot token expired or revoked. Check .env for TELEGRAM_BOT_TOKEN_ROBERT
# "409 Conflict" — another process is polling the same bot token (duplicate bot instance)
```

### Webhook path check (Discord ops channels)

```bash
# Test if webhooks work independently of the bot
WEBHOOK_URL=$(cat /root/.openclaw/reactor-webhook-url.txt 2>/dev/null)
if [ -n "$WEBHOOK_URL" ]; then
  curl -s -o /dev/null -w "%{http_code}" -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"content":"channel-health skill test — ignore this message"}'
  # 204 = webhook working
  # 401/403 = webhook URL expired, needs regeneration in Discord server settings
else
  echo "No webhook URL found at /root/.openclaw/reactor-webhook-url.txt"
fi
```

## Stability monitor status

The stability monitor runs every 5 minutes and can generate false alerts.
Check its state:

```bash
# Current state (is it reporting healthy?)
cat /root/.openclaw/stability-state.json 2>/dev/null | python3 -m json.tool

# Recent alert history
tail -20 /root/.openclaw/logs/stability-monitor.log | grep -E "ALERT|RESULT|healthy|HEALTH"

# Failure count (high number = long-running false positive loop)
grep -c "failures=" /root/.openclaw/logs/stability-monitor.log
```

**If failures count is very high (1000+)**: The monitor was likely stuck in a
false-positive loop. This was fixed on 2026-05-18 (see issue-false-alert-loop-20260518).
If it happens again, check: (1) Does `openclaw health` actually show channel status lines?
(2) Is the gateway event loop degraded causing empty health output?

## After fixing anything

Always verify the fix stuck:
```bash
# Run stability monitor once manually
timeout 60 bash /root/.openclaw/scripts/stability-monitor.sh 2>&1 | tail -5
# Should end with: RESULT_LABEL: healthy
```
