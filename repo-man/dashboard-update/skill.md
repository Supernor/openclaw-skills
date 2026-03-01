---
name: dashboard-update
description: Update the pinned dashboard message in #ops-dashboard with current system status using color-coded containers. Internal skill for nightly cron.
version: 2.0.0
author: repo-man
tags: [dashboard, monitoring, internal, components]
---

# dashboard-update

## Purpose
Refresh the pinned status summary in **#ops-dashboard** with current system health. Uses color-coded containers for at-a-glance reading.

## Target
- **Channel:** `1477754431780028598` (#ops-dashboard)
- **Pinned Message:** `1477754773951352903`

## Traffic Light Colors

| Status | Color | Code | When |
|--------|-------|------|------|
| Healthy | Green | `5763719` | All checks pass |
| Warning | Yellow | `16776960` | Non-critical issues (1 provider down, warnings in logs) |
| Critical | Red | `15548997` | 2+ providers down, backup failures, key drift |

## Steps

### 1. Gather data

```bash
cat /home/node/.openclaw/model-health.json | jq .
/home/node/.openclaw/scripts/key-drift-check.sh
/home/node/.openclaw/scripts/repo-health.sh
/home/node/.openclaw/scripts/log-audit.sh
```

### 2. Determine overall status

- **Green:** All providers healthy, no key drift, all repos reachable, no log warnings
- **Yellow:** 1 provider quarantined OR log warnings OR stale backups (>48h)
- **Red:** 2+ providers quarantined OR key drift detected OR repo unreachable OR backup failure

### 3. Edit pinned message with container

```json
{
  "action": "edit",
  "channel": "discord",
  "channelId": "1477754431780028598",
  "messageId": "1477754773951352903",
  "components": {
    "container": {
      "accentColor": <GREEN_YELLOW_OR_RED>
    },
    "text": "<formatted dashboard — see template below>",
    "blocks": []
  }
}
```

### 4. Dashboard template

Build the `text` field using this format. Keep it tight — this is the glance view.

**When green:**
```
**OpenClaw Dashboard** — ✅ All Systems Healthy
_<timestamp>_

**Providers** — 4/4 active
✅ gemini-3-flash · ✅ gemini-3.1-pro · ✅ gpt-5.3-codex · ✅ openrouter/auto

**Infra** — ✅ Keys 7/7 · ✅ Repos 3/3 · ✅ Disk <N>MB
**Backups** — ws: <age> · env: <age> · skills: <age>
**Cron** — Last: ✅ <time> · Next: 03:00 UTC
```

**When yellow:**
```
**OpenClaw Dashboard** — ⚠️ 1 Issue
_<timestamp>_

**Providers** — 3/4 active
✅ gemini-3-flash · ✅ gemini-3.1-pro · ⚠️ anthropic (billing) · ✅ openrouter/auto

**Infra** — ✅ Keys 7/7 · ✅ Repos 3/3 · ✅ Disk <N>MB
**Backups** — ws: <age> · env: <age> · skills: <age>
**Cron** — Last: ✅ <time> · Next: 03:00 UTC
```

**When red:**
```
**OpenClaw Dashboard** — 🚨 <N> Issues
_<timestamp>_

**Providers** — 2/4 active
✅ gemini-3-flash · 🚨 gemini-3.1-pro (rate-limit) · 🚨 anthropic (billing) · ✅ openrouter/auto

**Infra** — 🚨 Keys 6/7 (missing: GH_TOKEN) · ✅ Repos 3/3 · ✅ Disk <N>MB
**Backups** — ws: <age> · env: ⚠️ 3d ago · skills: <age>
**Cron** — Last: 🚨 FAILED <time> · Next: 03:00 UTC
```

### 5. Rules

- **Providers on one line** — use `·` as separator, status emoji before each name. Abbreviate model names (drop the `google/` prefix etc).
- **Infra on one line** — keys, repos, disk. Only show detail if something's wrong.
- **Backups on one line** — ages only. Flag if >48h with ⚠️.
- **Under 1500 chars** — leave room for Discord formatting overhead.
- **Never delete/recreate** — always edit message `1477754773951352903`.

### 6. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO dashboard-update "Updated: <green|yellow|red>"
```
