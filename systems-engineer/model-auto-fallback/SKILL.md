---
name: model-auto-fallback
description: "[Internal] Dynamically expand/contract the fallback chain based on provider health"
version: 2.0.0
author: system
tags: [models, health, fallback, internal]
---

# model-auto-fallback

**Internal skill — called by Ops Officer during heartbeat when chain is degraded.**

## Trigger
Run when `model-health.json` shows 2+ models in `fallbackChain.quarantined`.

## Steps

### 1. Check current state
```bash
/home/node/.openclaw/scripts/model-auto-fallback.sh status
```

### 2. Evaluate and act
```bash
/home/node/.openclaw/scripts/model-auto-fallback.sh check
```
The script handles all logic: expansion (2+ quarantined), contraction (recovered), or no-op. Returns JSON with `action`, details, and `restartRequired`.

### 3. Format result

**Expansion (`action: "expanded"`):**
```
🔄 **Fallback Chain Expanded**
Added emergency models: <list>
Quarantined: <list>
⚠️ Restart required for changes to take effect.
```

**Contraction (`action: "contracted"`):**
```
✅ **Fallback Chain Restored**
Removed emergency models: <list>
⚠️ Restart required for changes to take effect.
```

**Blocked (`action: "blocked"`):**
```
🚨 **CRITICAL** — Cannot add backups: openrouter itself is quarantined.
<N> providers down, no fallback options available.
```

## Notes
- Never remove original configured models — only add/remove emergency ones
- Script backs up openclaw.json before modifying
- Do NOT restart automatically — only Robert or explicit instruction
