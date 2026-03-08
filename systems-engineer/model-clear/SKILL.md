---
name: model-clear
description: Clear quarantine/cooldown for a provider or all providers
version: 2.0.0
author: system
tags: [models, health, recovery]
---

# model-clear

## Invoke
```
/model-clear anthropic       # Clear quarantine for anthropic
/model-clear google           # Clear cooldown for google
/model-clear all              # Clear all providers
```

## Steps

### 1. Run the script
```bash
/home/node/.openclaw/scripts/model-clear.sh <provider|all>
```
If no argument given, ask user which provider. Valid: `anthropic`, `google`, `openrouter`, `openai-codex`, `all`.

### 2. Format output
The script returns JSON with `status`, `profilesCleared`, `agents`, `billingWarning`, and `message`.

**Success:**
```
✅ Cleared quarantine for <provider>
  - Reset errorCount to 0 across <N> agents
  - Removed cooldown/disabled flags
  - Updated model-health.json
```

If `billingWarning` is true, add:
```
⚠️ Note: Credits for <provider> may still be exhausted. If the provider fails again, it will be re-quarantined automatically.
```

## Notes
- The model-health-monitor hook will re-evaluate on next poll (within 30s).

Intent: Resilient [I08]. Purpose: [P-TBD].
