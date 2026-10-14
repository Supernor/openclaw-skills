---
name: channel-health
description: Diagnose Discord and Telegram channel health — real status, not just what the monitor says
tags: [discord, telegram, channels, health, diagnosis, troubleshooting]
version: 1.0.0
---

Runs where: container

## Execution location
Shared files: host `/root/.openclaw/` = container `/home/node/.openclaw/`.
Read shared files using the container path. Host-only references below preserve
commands and flags for a host worker; never execute those payloads in the gateway.
Request the selected step with the container-accessible submission script:

```bash
bash /home/node/.openclaw/scripts/workshop-submit.sh "Host-only: <selected command, arguments, safeguards, required output>" spec-ops routine "" reactor-dispatch
```

The fifth argument is `host_op`. Submission returns a task ID, not completion.
Use `ops_query` with `SELECT id,status,outcome,result,errors FROM tasks WHERE id=<id>`;
wait for the required output and preserve the original step order and failure gates.
A `host-only payload:` prefix identifies request text, not a shell command.
Choose the applicable example, not every alternative in a reference block.
Use `chart_read`, `chart_search_compact`, and `chart_add` MCP tools for all chart
operations below instead of the host chart CLI. Use KnownSelf MCP for host-memory
operations; host service/container operations require a host request.

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
   Works independently of the bot. Uses `/root/.openclaw/reactor-webhook-url.txt`. — container shared-path reference: /home/node/.openclaw/reactor-webhook-url.txt
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
Host-only reference: request the applicable step through the route above.
```text
chart_read(id="issue-false-alert-loop-20260518")     # The alert loop bug and fix
chart_read(id="issue-discord-channel-unavailable-20260518")  # Discord 8-day outage
chart_read(id="procedure-discord-plugin-update")     # Discord plugin version management
chart_read(id="learning-discord-externalized")       # Why Discord needs special handling
chart_read(id="procedure-update-openclaw")           # Update procedure (includes channel checks)
```

## Quick check (use this first)

Container-local inspection: `openclaw health`, `openclaw plugins list`, and
`openclaw --version` run directly. For logs, installation, ownership repair,
restarts and the monitor script, request the corresponding host-only step below.
Plugin repairs must be persisted in the host vendor bind-mount setup so they
survive rebuilds. A runtime installation alone is not the completed repair.

Run the gateway health command and interpret the output:

Host-only reference: request the applicable step through the route above.
```text
# Step 1: Get health output
host-only payload: docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw health 2>&1 | grep -E "Telegram:|Discord:|Gateway"  # host-only reference; no container mount is assumed; request via workshop-submit host_op reactor-dispatch
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

Host-only reference: request the applicable step through the route above.
```text
# Step 1: Is the plugin installed?
host-only payload: docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw plugins list 2>&1 | grep discord  # host-only reference; no container mount is assumed; request via workshop-submit host_op reactor-dispatch

# Expected: a line showing @openclaw/discord with a version number
# If missing: plugin needs to be installed (see Fix below)

# Step 2: Is the plugin crashing?
host-only payload: docker compose -f /root/openclaw/docker-compose.yml logs --tail=50 openclaw-gateway 2>&1 | grep -E "\[discord\].*(exited|error|crash)"  # host-only reference; no container mount is assumed; request via workshop-submit host_op reactor-dispatch

# If you see "[discord] channel exited: Package subpath" — VERSION MISMATCH
# The plugin version is newer than the gateway and uses SDK features that don't exist yet.
# ERROR MEANING: "Package subpath './plugin-sdk/text-utility-runtime' is not defined"
#   = Plugin expects an SDK export the gateway doesn't have.
#   = Fix: install a plugin version that matches the gateway version.

# Step 3: What version is the gateway?
host-only payload: docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw --version 2>&1 | head -1  # host-only reference; no container mount is assumed; request via workshop-submit host_op reactor-dispatch

# Step 4: What Discord plugin versions exist?
host-only payload: docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway npm view @openclaw/discord versions --json 2>&1 | tail -10  # host-only reference; no container mount is assumed; request via workshop-submit host_op reactor-dispatch
```

### Fix: Install matching Discord plugin

**IMPORTANT VERSION RULE**: Plugin version must be <= gateway version.
If gateway is v2026.5.8, use @openclaw/discord@2026.5.7 (not 2026.5.12).

Host-only reference: request the applicable step through the route above.
```text
# Install plugin at version matching gateway (or closest lower version)
host-only payload: docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway \  # host-only reference; no container mount is assumed; request via workshop-submit host_op reactor-dispatch
  openclaw plugins install @openclaw/discord@VERSION --force

# Fix file permissions (plugin install modifies openclaw.json as root)
# ERROR IF SKIPPED: "EACCES: permission denied, open openclaw.json"
# MISLEADING SECONDARY ERROR: "gateway.mode is missing" (file can't be read, not actually missing)
chown 1000:1000 /root/.openclaw/openclaw.json  # container shared-path reference: /home/node/.openclaw/openclaw.json

# Restart gateway to load the new plugin
host-only payload: docker compose -f /root/openclaw/docker-compose.yml restart openclaw-gateway  # host-only reference; no container mount is assumed; request via workshop-submit host_op reactor-dispatch

# Wait 30 seconds for startup, then verify
sleep 30
host-only payload: docker compose -f /root/openclaw/docker-compose.yml exec -T openclaw-gateway openclaw health 2>&1 | grep "Discord:"  # host-only reference; no container mount is assumed; request via workshop-submit host_op reactor-dispatch
# Should show: Discord: configured
```

**Config is safe**: Plugin install does NOT touch your channel config, message
history, tokens, or channel mappings. It only installs code and updates the
plugin registry. Your Discord server setup, channels, and permissions are
preserved.

### Telegram not connecting

Host-only reference: request the applicable step through the route above.
```text
# Check gateway logs for Telegram errors
host-only payload: docker compose -f /root/openclaw/docker-compose.yml logs --tail=50 openclaw-gateway 2>&1 | grep -i telegram  # host-only reference; no container mount is assumed; request via workshop-submit host_op reactor-dispatch

# Common issues:
# "fetch timeout" — transient, usually resolves in next polling cycle
# "401 Unauthorized" — bot token expired or revoked. Check .env for TELEGRAM_BOT_TOKEN_ROBERT
# "409 Conflict" — another process is polling the same bot token (duplicate bot instance)
```

### Webhook path check (Discord ops channels)

This test posts an external message. Use it only when a delivery test is
authorized; otherwise inspect stored monitor state and logs.

Host-only reference: request the applicable step through the route above.
```text
# Test if webhooks work independently of the bot
WEBHOOK_URL=$(cat /root/.openclaw/reactor-webhook-url.txt 2>/dev/null)  # container shared-path reference: /home/node/.openclaw/reactor-webhook-url.txt
if [ -n "$WEBHOOK_URL" ]; then
  curl -s -o /dev/null -w "%{http_code}" -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d '{"content":"channel-health skill test — ignore this message"}'
  # 204 = webhook working
  # 401/403 = webhook URL expired, needs regeneration in Discord server settings
else
  echo "No webhook URL found at /root/.openclaw/reactor-webhook-url.txt"  # container shared-path reference: /home/node/.openclaw/reactor-webhook-url.txt
fi
```

## Stability monitor status

The stability monitor runs every 5 minutes and can generate false alerts.
Check its state:

Host-only reference: request the applicable step through the route above.
```text
# Current state (is it reporting healthy?)
cat /root/.openclaw/stability-state.json 2>/dev/null | python3 -m json.tool  # container shared-path reference: /home/node/.openclaw/stability-state.json

# Recent alert history
tail -20 /root/.openclaw/logs/stability-monitor.log | grep -E "ALERT|RESULT|healthy|HEALTH"  # container shared-path reference: /home/node/.openclaw/logs/stability-monitor.log

# Failure count (high number = long-running false positive loop)
grep -c "failures=" /root/.openclaw/logs/stability-monitor.log  # container shared-path reference: /home/node/.openclaw/logs/stability-monitor.log
```

**If failures count is very high (1000+)**: The monitor was likely stuck in a
false-positive loop. This was fixed on 2026-05-18 (see issue-false-alert-loop-20260518).
If it happens again, check: (1) Does `openclaw health` actually show channel status lines?
(2) Is the gateway event loop degraded causing empty health output?

## After fixing anything

Always verify the fix stuck:
Host-only reference: request the applicable step through the route above.
```text
# Run stability monitor once manually
timeout 60 bash /root/.openclaw/scripts/stability-monitor.sh 2>&1 | tail -5  # container shared-path reference: /home/node/.openclaw/scripts/stability-monitor.sh
# Should end with: RESULT_LABEL: healthy
```
