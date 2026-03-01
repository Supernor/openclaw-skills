# openclaw-skills

Custom skills and hooks for the OpenClaw deployment.

## Structure

```
captain/        — Skills in the Captain (main) workspace (shared, model health)
repo-man/       — Skills in the Repo-Man (spec-github) workspace
quartermaster/  — Skills in the Quartermaster (spec-projects) workspace
hooks/          — Custom managed hooks (~/.openclaw/hooks/)
```

## Skills by Agent

### Captain (shared workspace)
| Skill | Command | Type |
|-------|---------|------|
| model-status | /model-status | user-invocable |
| model-clear | /model-clear | user-invocable |
| model-failover-notify | internal | heartbeat |
| model-auto-fallback | internal | heartbeat |

### Repo-Man
| Skill | Command | Type |
|-------|---------|------|
| key-drift-check | /key-drift | user-invocable |
| workspace-backup | /ws-backup | user-invocable |
| env-backup | /env-backup | user-invocable |
| repo-health | /repo-health | user-invocable |
| rotate-key | /rotate | user-invocable |
| error-report | /error-report | user-invocable |
| log-decision | /decision | user-invocable |
| log-event | internal | every operation |

### Quartermaster
| Skill | Command | Type |
|-------|---------|------|
| decide | /decide | user-invocable |
| decisions | /decisions | user-invocable |
| pin-decisions | /pin | user-invocable |
| audit | /audit | user-invocable |
| project | /project | user-invocable |
| archive | /archive | user-invocable |
| topic | /topic | user-invocable |

## Hooks
| Hook | Event | Description |
|------|-------|-------------|
| model-health-monitor | gateway:startup | Polls auth profiles every 30s, writes health state |

## Maintained By
- Claude Code (VPS host) — creates/modifies skills and hooks
- Repo-Man — pushes updates to this repo
