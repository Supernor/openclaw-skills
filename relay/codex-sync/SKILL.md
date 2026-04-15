# Skill: codex-sync
Description: Detect when Codex OAuth is failing and fix it by syncing fresh tokens to the gateway. This is the #1 most common system issue — Codex tokens expire, gateway falls back to Mistral (slow), everything degrades.

## Triggers
- You notice your OWN responses are slow (you're running on Mistral fallback instead of Codex)
- Robert says "you're slow", "Relay is slow", "why is everything slow"
- Robert says "/reauth" or "fix codex" or "refresh auth"
- You see "OAuth token refresh failed" or "rate_limit" in recent errors
- You see "FailoverError" in your session context
- Gateway model fallback decisions show Codex failing

## How to detect you're on Mistral
If your responses feel different or Robert says you're slow, you're probably on Mistral fallback.
The gateway logs show: `model fallback decision: decision=candidate_failed requested=openai-codex ... reason=auth`

## Fix: Two Steps

### Step 1: Sync tokens (fixes 90% of cases)
The host CLI usually has valid tokens — they just haven't been copied to the gateway container.

```
Tool: ops_insert_task
agent: relay
task: Sync Codex tokens to gateway
meta: {"host_op": "codex-reauth-telegram", "chat_id": "CURRENT_CHAT_ID"}
urgency: critical
```

This runs `/root/.openclaw/scripts/codex-reauth-telegram.sh` which:
1. Checks both Codex pools (A + B)
2. If host tokens are valid → syncs to gateway → restarts gateway → done
3. If host tokens are ALSO expired → sends device auth URL to Telegram for Robert to tap

### Step 2: If sync didn't fix it
Tell Robert: "Codex tokens are expired on the host too. I sent you an auth link — tap it to re-authorize."
The script handles this automatically — a tappable link appears in chat.

## After the fix
- Gateway restarts (takes ~10 seconds)
- Your next response should be faster (back on Codex)
- Tell Robert: "Tokens synced. I should be back on Codex now."

## Important
- Do NOT try to fix this by editing files yourself — use the host_op task
- The sync script handles both pools, gateway restart, and verification
- This skill should be used PROACTIVELY — if you detect you're on fallback, fix it without being asked
