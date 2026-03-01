---
name: model-auto-fallback
description: "[Internal] Dynamically expand/contract the fallback chain based on provider health"
version: 1.0.0
author: system
tags: [models, health, fallback, internal]
---

# model-auto-fallback

**Internal skill — called by Repo-Man during heartbeat when chain is degraded.**

## Trigger Condition

Run when `model-health.json` shows 2+ models in `fallbackChain.quarantined`.

## Emergency Backup Pool

These models can be temporarily added to the fallback chain:

| Model | Provider | Notes |
|-------|----------|-------|
| `openrouter/anthropic/claude-sonnet-4-5` | openrouter | Via OpenRouter routing |
| `openrouter/google/gemini-2.0-flash` | openrouter | Older but stable |
| `openrouter/meta-llama/llama-4-maverick` | openrouter | Open-weight fallback |

**Only add models from providers that are currently healthy.**

## Steps

### 1. Read model-health.json

```bash
cat /home/node/.openclaw/model-health.json
```

Check `fallbackChain.quarantined` count.

### 2. Determine action

**If 2+ quarantined AND no emergency models already added:**

a. Check which providers are healthy
b. Select backup models from healthy providers only
c. Read `openclaw.json`:

```bash
cat /home/node/.openclaw/openclaw.json
```

d. Add backup models to `agents.defaults.model.fallbacks` array (append, don't replace)
e. Track which models were added by writing to `model-health.json` under a new key:

```json
{
  "fallbackChain": {
    "configured": ["...original..."],
    "quarantined": ["..."],
    "emergency": ["openrouter/google/gemini-2.0-flash", "openrouter/meta-llama/llama-4-maverick"]
  }
}
```

f. Write updated `openclaw.json` (atomic write via temp+rename)
g. Report what was added

**If previously expanded AND quarantined count is now 0 or 1:**

a. Read `model-health.json` to find emergency models
b. Remove those models from `openclaw.json` fallbacks array
c. Clear the `emergency` key from `model-health.json`
d. Write both files atomically
e. Report what was removed

### 3. Restart note

After modifying `openclaw.json`, the agent should note:
```
⚠️ Config updated. Changes take effect on next gateway restart.
Run: docker compose restart openclaw-gateway
```

However, do NOT restart automatically — only Robert or explicit instruction should trigger restarts.

### 4. Confirm

Report to Relay/Robert:

**Expansion:**
```
🔄 **Fallback Chain Expanded**
Added emergency models:
  - openrouter/google/gemini-2.0-flash
  - openrouter/meta-llama/llama-4-maverick
Quarantined: <list>
Chain now: <full list>
⚠️ Restart required for changes to take effect.
```

**Contraction:**
```
✅ **Fallback Chain Restored**
Removed emergency models: <list>
All configured models healthy.
⚠️ Restart required for changes to take effect.
```

## Notes
- Never remove the original configured models — only add/remove emergency ones.
- Never add a model from a quarantined provider.
- If openrouter itself is quarantined, no emergency models can be added (all are via openrouter). Report this as critical.
- This skill modifies `openclaw.json` — always back up first.
