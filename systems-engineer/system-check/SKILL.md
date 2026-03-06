---
name: system-check
description: Quick health check of the entire OpenClaw stack using native CLI commands
tags: [health, monitoring, ops, system]
version: 1.0.0
---

# System Check

One-command health check of the full stack.

## When to use
- Start of session — verify system is healthy before working
- After config changes or restarts
- When something feels off
- Before running Reactor tasks

## Quick check (run all in parallel)

```bash
# Gateway health
oc health --json

# Container status
docker compose ps

# Security audit
oc security audit --json

# Cron jobs
oc cron list --json

# Plugin status
oc plugins list --json

# Agent list
oc agents list --json

# Chartroom stats
oc ltm stats

# Reactor service
systemctl is-active openclaw-reactor
```

## Deeper check

```bash
# Doctor (full diagnostic)
oc doctor

# Model status
oc models aliases list

# Active sessions
oc sessions --all-agents --json

# Memory index status
oc memory status

# Disk usage
df -h / | tail -1

# Bridge status
bash /root/.openclaw/scripts/bridge.sh status
```

## Response format
Report: healthy/degraded/down for each subsystem. Flag anything needing attention.
