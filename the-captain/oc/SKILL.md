---
name: oc
description: OpenClaw CLI quick-reference. Maps common operations to oc commands. Use this instead of docker compose exec.
version: 1.1.0
author: reactor
tags: [oc, cli, openclaw, commands, operations, docker]
trigger:
  command: /oc
  keywords:
    - openclaw command
    - oc command
    - docker compose exec
    - gateway command
    - agent command
    - how to
---

# /oc — OpenClaw CLI Quick Reference

NEVER use `docker compose exec openclaw-gateway npx openclaw ...` — use `oc` directly.

## Agent Communication
```bash
oc agent --message "<text>"                    # talk to default agent
oc agent --message "<text>" --to <agent-id>    # talk to specific agent
oc agent --message "<text>" --json             # JSON output
oc agent --message "<text>" --timeout 300      # long task
oc agent --message "<text>" --deliver          # send reply to channel
```

## Health & Status
```bash
oc health                    # gateway + channel health
oc doctor                    # diagnose problems
oc doctor --deep             # deep diagnosis
oc status                    # channel health + recent recipients
oc status --deep             # probes + detailed status
```

## Config
```bash
oc config get <dot.path>     # read config value
oc config set <dot.path> <value>  # set config value
oc config unset <dot.path>   # remove config value
oc config validate           # check config against schema
oc config file               # print config file path
```

## Models
```bash
oc models status                    # show current model config
oc models aliases list              # list model aliases
oc models aliases add <name> <model>  # add alias
oc models fallbacks list            # list fallback chain
oc models fallbacks add <model>     # add fallback
oc models auth add                  # add auth profile
oc models auth order get            # view auth priority
```

## Gateway
```bash
oc gateway status            # gateway process status
oc gateway restart           # restart gateway
oc gateway start             # start gateway
oc gateway stop              # stop gateway
```

## Channels
```bash
oc channels list             # list configured channels
oc channels status           # channel connection status
```

## Sessions & Skills
```bash
oc sessions                  # list sessions
oc skills list               # list all skills
oc skills check              # check skill readiness
oc skills info <name>        # skill details
```

## Agents
```bash
oc agents list               # list all agents
```

## Messaging
```bash
oc message send --to <dest> --body "<text>"   # send a message
```

## Logs & Monitoring
```bash
oc logs                      # tail gateway logs
backbone status              # backbone listener state (host CLI)
backbone snapshot            # one-time backbone dump (host CLI)
```

## Security
```bash
oc secrets reload            # reload secrets from env/files
oc secrets audit             # audit secret configuration
```

## Other
```bash
oc cron list                 # list cron jobs
oc memory search "<query>"   # search agent memory
oc hooks list                # list hooks
```

## Still needs docker compose
```bash
docker compose up -d openclaw-gateway          # recreate (picks up new .env vars)
docker compose exec --user root openclaw-gateway <cmd>  # root installs
docker cp <file> $(docker compose ps -q openclaw-gateway):<dest>  # copy files in
```
