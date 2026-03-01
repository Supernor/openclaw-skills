---
name: key-drift-check
description: Compare /app/.env against the canonical key list. Report any missing, extra, or unexpected keys. Runs automatically on session start and nightly. Invoke manually with /key-drift.
version: 1.0.0
author: repo-man
tags: [security, keys, drift, session-start]
---

# key-drift-check

## When It Runs

- Automatically on every session start (via BOOTSTRAP.md)
- Nightly cron at 03:00 UTC
- On demand: `/key-drift`

## Canonical Key List

```
OPENCLAW_GATEWAY_TOKEN
OPENAI_API_KEY
GH_TOKEN
OPENCLAW_PROD_ANTHROPIC_KEY
OPENCLAW_PROD_GOOGLE_AI_KEY
OPENCLAW_PROD_OPENROUTER_KEY
OPENCLAW_PROD_DISCORD_TOKEN
```

Expected count: **7**

## Steps

### 1. Extract actual keys from .env (names only, never values)
```bash
grep -E '^[A-Z_]+=.' /app/.env | cut -d= -f1 | sort > /tmp/env-keys-actual.txt
cat /tmp/env-keys-actual.txt
```

### 2. Compare against canonical list
```bash
# Write canonical list
cat > /tmp/env-keys-canonical.txt << 'EOF'
GH_TOKEN
OPENCLAW_GATEWAY_TOKEN
OPENCLAW_PROD_ANTHROPIC_KEY
OPENCLAW_PROD_DISCORD_TOKEN
OPENCLAW_PROD_GOOGLE_AI_KEY
OPENCLAW_PROD_OPENROUTER_KEY
OPENAI_API_KEY
EOF

# Find missing keys (in canonical, not in actual)
comm -23 /tmp/env-keys-canonical.txt /tmp/env-keys-actual.txt > /tmp/keys-missing.txt

# Find extra keys (in actual, not in canonical)
comm -13 /tmp/env-keys-canonical.txt /tmp/env-keys-actual.txt > /tmp/keys-extra.txt
```

### 3. Also check GitHub Secrets count
```bash
gh secret list --repo NowThatJustMakesSense/openclaw-config
```
Compare count against canonical list. Names must match.

### 4. Evaluate and log

**All match, counts correct:**
- log-event: INFO, skill=key-drift-check, "PASS: 7/7 keys present, GitHub Secrets match"
- Update LAST_RUN.md: PASS

**Missing keys:**
- log-event: ERROR, skill=key-drift-check
- Command: the grep above
- Stderr: list of missing key names
- Next action: "Alerting Robert. Manual key restore required."
- Discord: `[Repo-Man] ERROR: key-drift-check FAIL. Missing keys: <names>. Check /app/.env immediately.`

**Extra/unexpected keys:**
- log-event: WARN, skill=key-drift-check
- Next action: "Reporting to Robert for review. No automatic action taken."

**GitHub Secrets mismatch:**
- log-event: WARN, skill=key-drift-check
- Report count discrepancy and which names differ

## Output (Discord summary)

Success: `[Repo-Man] key-drift-check ✅ 7/7 keys present. GitHub Secrets: 7/7 match.`  
Failure: `[Repo-Man] key-drift-check ❌ Missing: OPENCLAW_PROD_ANTHROPIC_KEY. GitHub Secrets: 6/7. Action required.`
