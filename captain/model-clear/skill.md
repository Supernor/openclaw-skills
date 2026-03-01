---
name: model-clear
description: Clear quarantine/cooldown for a provider or all providers
version: 1.0.0
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

### 1. Identify target provider

Parse the argument. If no argument given, ask user which provider to clear.
Valid providers: `anthropic`, `google`, `openrouter`, `openai-codex`, or `all`.

### 2. Read current auth profiles for ALL agents

Read each auth-profiles.json:

```bash
for agent in relay main spec-github spec-projects; do
  echo "=== $agent ==="
  cat /home/node/.openclaw/agents/$agent/agent/auth-profiles.json
done
```

### 3. Clear matching profile stats

For each auth-profiles.json where a matching provider profile exists in `usageStats`:

Using `jq` or equivalent, update the file to:
- Set `errorCount` to `0`
- Remove `cooldownUntil`
- Remove `disabledUntil`
- Remove `disabledReason`
- Remove `failureCounts`
- Keep `lastUsed` and `lastFailureAt` (audit trail)

Write the updated JSON back to the same file.

**IMPORTANT:** Use a read-modify-write pattern. Read the full JSON, modify only the usageStats for matching profiles, write back. Do not clobber other data.

Example jq for clearing anthropic:

```bash
jq '
  .usageStats |= with_entries(
    if (.key | startswith("anthropic:"))
    then .value |= (del(.cooldownUntil, .disabledUntil, .disabledReason, .failureCounts) | .errorCount = 0)
    else .
    end
  )
' /home/node/.openclaw/agents/$agent/agent/auth-profiles.json > /tmp/auth-profiles-$agent.json \
  && mv /tmp/auth-profiles-$agent.json /home/node/.openclaw/agents/$agent/agent/auth-profiles.json
```

For `all`, clear every profile's error state regardless of provider prefix.

### 4. Update model-health.json

Read `/home/node/.openclaw/model-health.json`, set the cleared provider(s) status to `"healthy"`, reason to `"cleared"`, and remove from `fallbackChain.quarantined`.

Write back atomically (temp file + rename).

### 5. Log the action

Append a notification to `/home/node/.openclaw/model-health-notifications.jsonl`:

```json
{"ts":"<ISO>","type":"recovery","provider":"<provider>","reason":"manual-clear","message":"Provider <provider> manually cleared by user"}
```

### 6. Confirm to user

```
✅ Cleared quarantine for <provider>
  - Reset errorCount to 0 across all agents
  - Removed cooldown/disabled flags
  - Updated model-health.json
```

If clearing a billing-disabled provider, add warning:
```
⚠️ Note: Credits for <provider> may still be exhausted. If the provider fails again, it will be re-quarantined automatically.
```

## Notes
- This modifies auth-profiles.json and model-health.json.
- The model-health-monitor hook will re-evaluate on next poll (within 30s).
- If credits are truly exhausted, the provider will be re-quarantined on next failure.
