---
name: ops-digest
description: Compact 24-hour operational briefing. Pulls from ops.db, model-health, cron status, and recent notifications.
version: 1.0.0
author: repo-man
tags: [ops, digest, internal, components]
---

# ops-digest

## Purpose
Produce a compact operational summary covering the last 24 hours. One card, one read, full picture.

## When to run
- On `/ops-digest` command (user-invocable)
- As part of nightly cron (before dashboard-update, after scripts complete)
- On session start when Robert asks "what happened?"

## Target
- **Channel:** #ops-nightly (from registry) when run via cron
- **Direct reply** when run via user command

---

## Steps

### 1. Gather data

```bash
SCRIPTS="/home/node/.openclaw/scripts"
BASE="/home/node/.openclaw"

# Model health — current state
MODEL_HEALTH=$(cat "$BASE/model-health.json" 2>/dev/null)

# Recent health events (last 24h)
CUTOFF=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
HEALTH_EVENTS=$(tail -50 "$BASE/model-health-notifications.jsonl" 2>/dev/null | jq -sc "[.[] | select(.ts > \"$CUTOFF\")]")

# Config changes (last 24h)
CONFIG_CHANGES=$("$SCRIPTS/ops-db.sh" config recent 24 2>/dev/null || echo "[]")

# Incidents
OPEN_INCIDENTS=$("$SCRIPTS/ops-db.sh" incident list 2>/dev/null || echo "[]")

# Cron status
CRON_STATUS=$(jq -c '[.jobs[] | {name: .name, lastStatus: .state.lastStatus, lastRunAt: (.state.lastRunAtMs // 0 | . / 1000 | strftime("%Y-%m-%dT%H:%M:%SZ"))}]' "$BASE/cron/jobs.json" 2>/dev/null || echo "[]")

# DB stats
DB_STATS=$("$SCRIPTS/ops-db.sh" stats 2>/dev/null || echo "{}")

# Disk usage
DISK=$(du -sm "$BASE" 2>/dev/null | awk '{print $1}')
```

### 2. Format the digest

Build a single card with these sections:

**Template:**
```
📊 **Ops Digest** — <date>

**Providers**
✅ google — healthy
✅ openai-codex — healthy
⚠️ openrouter — rate-limited (since 14:30)

**Health Events** (last 24h)
🔴 1 failure: openrouter rate-limited at 14:22
🟢 0 recoveries
📋 0 open incidents

**Cron**
✅ repo-man-nightly — passed (03:01)
✅ project-audit — passed (00:01)
⏭️ context-audit — next Mar 31

**Config**
🔧 2 changes (last: "updated registry v3")

**System**
💾 17 MB disk | 📦 ops.db: 88 KB, 48 rows
```

### 3. Formatting rules

- **One card, blue accent** (5814783) — informational
- **Providers:** emoji per status: ✅ healthy, ⚠️ rate-limited, 🔴 quarantined
- **Health events:** count failures and recoveries in the window
- **Cron:** show last status per job. Use ✅ passed, ❌ error, ⏭️ not-yet-run
- **Config:** count changes, show last change description if available
- **System:** disk + DB size in one line
- If everything is green (0 failures, 0 incidents, all cron passed): add `🟢 All systems nominal` at the top

### 4. Post as component card

```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "<from registry: ops-nightly or direct reply>",
  "components": {
    "container": { "accentColor": 5814783 },
    "text": "<formatted digest>"
  }
}
```

### 5. Truncation rules

- Max 3 health events shown, then `+ N more`
- Config changes: show count + last entry only
- Provider list: always show all (max ~6 providers)

## Skip conditions

Never skip — always produce a digest even if everything is green. "All clear" is valuable information.
