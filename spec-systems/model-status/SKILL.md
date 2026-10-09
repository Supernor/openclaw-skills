---
name: model-status
description: Show current model/provider health, fallback chain status, and recent failures
version: 1.0.0
author: system
tags: [models, health, monitoring]
---

# model-status

## Invoke

```
/model-status          # Full dashboard
/model-status brief    # One-line per provider
```

## Steps

### 1. Read model health state

```bash
cat /home/node/.openclaw/model-health.json
```

If the file does not exist, report: "Model health monitor has not run yet. The `model-health-monitor` hook may not be loaded. Check gateway logs."

### 2. Read current auth profile stats (for live data)

```bash
cat /home/node/.openclaw/agents/relay/agent/auth-profiles.json | jq '.usageStats'
```

### 3. Read recent notifications

```bash
tail -10 /home/node/.openclaw/model-health-notifications.jsonl
```

### 4. Format dashboard

Display using this format:

```
📊 Model Health Dashboard
Last checked: <lastChecked>

Provider Status:
  ✅ google — healthy
  ❌ anthropic — quarantined (billing) until <time>
  ⚠️ openrouter — rate-limited

Fallback Chain:
  1. google/gemini-3-flash-preview ✅
  2. google/gemini-3.1-pro-preview ✅
  3. openai-codex/gpt-5.3-codex ✅
  4. openrouter/auto ⚠️

Recent Events (last 5):
  [time] ❌ anthropic billing — credits exhausted
  [time] ✅ google recovered

Active: 3/4 models | Chain health: DEGRADED
```

Status icons:
- ✅ = healthy
- ⚠️ = rate-limited / cooldown
- ❌ = quarantined / disabled

If `brief` argument: one line per provider, e.g. `google: ✅ | anthropic: ❌ billing | openrouter: ✅ | openai-codex: ✅`

## Notes
- Read-only. Does not modify any files.
- Uses data from model-health-monitor hook. If stale (>2min), warn user.

Intent: Observable [I13]. Purpose: [P-TBD].
