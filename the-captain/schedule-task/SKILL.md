---
name: schedule-task
description: Schedule recurring or one-shot tasks using OpenClaw's built-in cron system
tags: [cron, scheduling, automation]
version: 1.0.0
---

# Schedule Task

Create scheduled jobs that run agents automatically.

## When to use
- Recurring tasks (daily digests, health checks, nightly audits)
- One-shot delayed tasks ("do this in 20 minutes")
- Dead man's switch patterns (schedule undo, cancel if healthy)

## Commands

### One-shot (run once, then delete)
```bash
oc cron add --at "+20m" --agent spec-research --message "Check AI news" --delete-after-run --json
```

### Recurring
```bash
oc cron add --cron "0 8 * * *" --agent main --message "Morning system check" --json
oc cron add --every 1h --agent spec-security --message "Quick security scan" --json
```

### With Discord delivery
```bash
oc cron add --cron "0 9 * * *" --agent main --message "Daily digest" --announce --json
```

### Manage
```bash
oc cron list --json              # List all jobs
oc cron run <job-id> --json      # Run now (debug)
oc cron disable <job-id>         # Pause
oc cron enable <job-id>          # Resume
oc cron rm <job-id>              # Delete
oc cron runs --json              # Run history
```

## Dead man's switch pattern
```bash
# 1. Schedule the undo
oc cron add --at "+10m" --agent spec-dev --message "ROLLBACK: revert config change X" --delete-after-run --json
# 2. Make the change
# 3. Test
# 4. If healthy, cancel: oc cron rm <job-id>
```

## Rules
- Always include `--delete-after-run` for one-shot jobs
- Use `--announce` to make results visible in Discord
- Prefer `--every` over raw cron expressions for readability
