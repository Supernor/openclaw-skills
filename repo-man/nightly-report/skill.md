---
name: nightly-report
description: Post nightly cron results to #ops-nightly as color-coded summary cards with raw data in a thread. Internal skill for nightly cron.
version: 2.0.0
author: repo-man
tags: [nightly, monitoring, internal, components]
---

# nightly-report

## Purpose
Post the nightly cron results to **#ops-nightly** as human-glanceable summary cards. Raw script output goes in a thread for agent reference.

## Target
- **Channel:** `1477754636046831738` (#ops-nightly)

## Steps

### 1. Collect script results

By the time this runs, Phase 1 scripts have already executed. Collect their JSON outputs.

### 2. Determine per-section status

| Section | Green | Yellow | Red |
|---------|-------|--------|-----|
| Keys | 0 missing, 0 extra | — | Any missing or extra |
| Backups | All pushed successfully | Push succeeded with warnings | Any push failed |
| Repos | All 3 reachable, secrets match | — | Any unreachable |
| Logs | 0 warnings, all rotations OK | Warnings present but non-critical | Failed persistence or rotation |
| Providers | All healthy | 1 quarantined | 2+ quarantined |

### 3. Post summary card

Send one container message — the "glance" card. Color = worst status across all sections.

```json
{
  "action": "send",
  "channel": "discord",
  "channelId": "1477754636046831738",
  "components": {
    "container": {
      "accentColor": <OVERALL_COLOR>
    },
    "text": "<summary — see template>"
  }
}
```

**Summary template:**
```
**Nightly Run — <date>** <overall_emoji>

✅ **Keys** — 7/7 present, no drift
✅ **Backups** — ws ✅ env ✅ skills ✅ (all pushed)
✅ **Repos** — config ✅ workspace ✅ skills ✅
✅ **Logs** — persisted 1 gateway log, pruned 0 sessions, 0 warnings
✅ **Providers** — 4/4 healthy

_Thread below has full script output._
```

When something fails, the emoji and detail change:
```
🚨 **Keys** — 6/7 present — missing: `GH_TOKEN`
⚠️ **Logs** — 2 warnings: session prune skipped (min 3 rule), config-audit at 980/1000 lines
```

### 4. Create thread with raw data

Create a thread on the summary message:

```json
{
  "action": "thread-create",
  "channel": "discord",
  "channelId": "1477754636046831738",
  "messageId": "<summary_message_id>",
  "name": "Nightly <date> — Raw Output",
  "autoArchiveDuration": 1440
}
```

Then post each script's JSON output as separate thread replies:

```
**key-drift-check.sh**
```json
<raw JSON output>
```

**log-audit.sh**
```json
<raw JSON output>
```
```

This preserves full data for agents without cluttering the channel.

### 5. Rules

- **One summary card per night** — never multiple messages in the channel
- **Thread for raw data** — agents that need script output read the thread
- **Abbreviate in summary** — "persisted 1 gateway log" not the full path
- **Worst color wins** — if keys are green but providers are red, the card is red
- **Skip sections that are fine** — if everything in a section is green, one line is enough. Expand only the problem sections.

### 6. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO nightly-report "Posted: <green|yellow|red>, <N> sections flagged"
```
