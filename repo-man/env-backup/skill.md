---
name: env-backup
description: Generate a .env.template from /app/.env (key names only, no values) and push to openclaw-config repo. Runs nightly and on demand. Invoke with /env-backup.
version: 1.0.0
author: repo-man
tags: [backup, env, secrets, github]
---

# env-backup

## When It Runs

- Nightly cron at 03:00 UTC
- On demand: `/env-backup`
- After any key rotation

## What Gets Pushed

`.env.template` — key names with empty values. No secrets. Ever.

Example output:
```
OPENCLAW_GATEWAY_TOKEN=
OPENAI_API_KEY=
GH_TOKEN=
OPENCLAW_PROD_ANTHROPIC_KEY=
OPENCLAW_PROD_GOOGLE_AI_KEY=
OPENCLAW_PROD_OPENROUTER_KEY=
OPENCLAW_PROD_DISCORD_TOKEN=
```

## Steps

### 1. Generate template (CRITICAL — key names only)
```bash
grep -E '^[A-Z_]+=.' /app/.env | sed 's/=.*/=/' > /tmp/env.template
```

**Before proceeding: verify no values leaked**
```bash
# This must output nothing. If it outputs anything, STOP and log FATAL.
grep -E '^[A-Z_]+=.+' /tmp/env.template
```

If the verification grep finds any non-empty values: log FATAL, delete `/tmp/env.template`, alert Robert, STOP. Never push a file with real values.

### 2. Ensure local clone exists
```bash
REPO_PATH="/home/node/.openclaw/workspace-spec-github/openclaw-config"

if [ ! -d "$REPO_PATH/.git" ]; then
  git clone https://github.com/NowThatJustMakesSense/openclaw-config.git "$REPO_PATH"
fi
```

### 3. Copy template into repo
```bash
cp /tmp/env.template "$REPO_PATH/.env.template"
```

### 4. Commit and push
```bash
cd "$REPO_PATH"
git add .env.template
git diff --cached --quiet && echo "NO_CHANGES" || git commit -m "[env-backup] $(date -u +%Y-%m-%dT%H:%M:%SZ) update .env.template"
git push origin main
```

### 5. Log result

**No changes:**
- log-event: INFO "env-backup: template unchanged, no push needed"

**Pushed:**
- log-event: INFO "env-backup: PASS. .env.template updated with N keys."

**Value leak detected:**
- log-event: FATAL "env-backup: ABORTED — value found in template. Possible sed failure."
- Discord: `[Repo-Man] ⚠️ FATAL: env-backup aborted. Possible secret leak to template file. Manual review required immediately.`

**Push failed:**
- log-event: ERROR with full stderr
- Discord: `[Repo-Man] ERROR: env-backup push failed. Template generated but not pushed.`
