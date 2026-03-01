---
name: nightly-report
description: Post nightly cron results to #ops-nightly as color-coded summary cards with raw data in a thread. Internal skill for nightly cron.
version: 3.0.0
author: repo-man
tags: [nightly, monitoring, internal, components]
---

# nightly-report

## Purpose
Post nightly cron results to **#ops-nightly** as a human-glanceable summary card. Raw data goes in a thread.

## Template
Read `~/.openclaw/templates/nightly-report.txt` for Discord card format, per-section status thresholds, and thread format.

## Registry
```bash
CHANNEL=$(jq -r '.discord.channels."ops-nightly"' ~/.openclaw/registry.json)
```

## Steps

### 1. Collect script results
Phase 1 scripts already ran. Collect their JSON outputs.

### 2. Determine per-section status
See template for Green/Yellow/Red thresholds per section (Keys, Backups, Repos, Logs, Providers).

### 3. Post summary card
Send one container message. Color = worst status across all sections.
- Green `5763719` / Yellow `16776960` / Red `15548997`

### 4. Create thread with raw data
Thread name: `Nightly <date> — Raw Output` (autoArchive: 1440min)
Post each script's JSON output as separate thread replies.

### 5. Rules
- One summary card per night
- Worst color wins overall
- Abbreviate in summary, full data in thread

### 6. Log result
```bash
/home/node/.openclaw/scripts/log-event.sh INFO nightly-report "Posted: <green|yellow|red>, <N> sections flagged"
```
