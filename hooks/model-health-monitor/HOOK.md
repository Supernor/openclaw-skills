---
name: model-health-monitor
description: "Polls auth-profile state every 30s and writes model health status + notifications"
metadata:
  {
    "openclaw":
      {
        "emoji": "🏥",
        "events": ["gateway:startup"],
        "always": true,
      },
  }
---

# model-health-monitor

Monitors auth profile usage stats for all agents. Detects provider failures
(billing, rate-limit, auth errors) and writes structured health data for
skills and agents to consume.

## Outputs

- `~/.openclaw/model-health.json` — current provider health snapshot
- `~/.openclaw/model-health-notifications.jsonl` — append-only failure/recovery log
