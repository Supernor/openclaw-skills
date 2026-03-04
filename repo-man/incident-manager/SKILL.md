---
name: incident-manager
description: Create/close GitHub Issues for model health incidents. Runs incident-manager.sh script.
version: 1.0.0
author: repo-man
tags: [incidents, github, models, health]
---

# incident-manager

## Invoke
```
/incident open <provider> <reason> <message>
/incident close <provider> [message]
/incident list
/incident check <provider>
```

## Integration with model health monitoring

On heartbeat, when processing model-health-notifications.jsonl:

**On failure notification:**
```bash
/home/node/.openclaw/scripts/incident-manager.sh open <provider> <reason> "<message>"
```
- If an issue already exists for that provider, adds a comment instead of creating a duplicate.

**On recovery notification:**
```bash
/home/node/.openclaw/scripts/incident-manager.sh close <provider> "<recovery message>"
```

**On /model-status:**
```bash
/home/node/.openclaw/scripts/incident-manager.sh list
```
Include open incidents in the dashboard output.

## Labels used

- `incident` — all incident issues
- `provider:<name>` — per-provider label (e.g., `provider:anthropic`)
- `automated` — created by script, not human

## Notes
- Issues are created in the `openclaw-config` repo
- Robert gets GitHub notification emails for free — no Discord token cost
- Labels are auto-created on first use by `gh issue create`
- Do NOT create issues manually — always use the script for consistency
