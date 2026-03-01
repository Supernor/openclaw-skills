# openclaw-skills

Custom skills, hooks, and shell scripts for a multi-agent [OpenClaw](https://github.com/openclaw/openclaw) deployment.

## Architecture

This deployment runs 4 specialized agents, each with targeted skills:

| Agent | Role | Skills |
|-------|------|--------|
| **Relay** | Human-facing, all user communication | — |
| **Captain** | Router/dispatcher | model-status, model-clear, model-failover-notify, model-auto-fallback |
| **Repo-Man** | Infra, backups, GitHub, model health | key-drift, backups, error-report, incident-manager, dashboard, nightly reporting |
| **Quartermaster** | Projects, decisions, auditing | decide, audit, project, archive, topic |

## Structure

```
captain/        — Shared workspace skills (model health)
repo-man/       — Repo-Man skills (ops, backups, Discord reporting)
quartermaster/  — Quartermaster skills (projects, auditing)
hooks/          — Custom managed hooks
scripts/        — Shell scripts (all output JSON)
```

## Shell Scripts

14 deterministic shell scripts at `~/.openclaw/scripts/`, all outputting JSON:

| Script | Purpose |
|--------|---------|
| `key-drift-check.sh` | Compare env keys vs canonical list |
| `env-backup.sh` | Generate .env.template, push to GitHub |
| `ws-backup.sh` | Push workspace MD files to GitHub |
| `skills-backup.sh` | Push skills + hooks + scripts to GitHub |
| `repo-health.sh` | Check 3 repos + secrets + logging |
| `log-event.sh` | Structured logging |
| `gateway-log-query.sh` | Query gateway JSON logs |
| `incident-manager.sh` | GitHub Issues for incidents |
| `config-tag.sh` | Tag config repo for rollback |
| `log-audit.sh` | Audit all logs: persist, prune, rotate |
| `racp-split.sh` | Split RACP-marked docs into per-agent versions |
| `registry.sh` | Query shared registry (IDs, paths, constants) |
| `context-snapshot.sh` | Generate pre-flight context snapshot |
| `ops-db.sh` | Query/mutate the ops SQLite database |

## Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `model-health-monitor` | `gateway:startup` | Polls auth profiles every 30s, writes structured health state |

## AI Attribution

All code in this repository was written by **Claude Code** (Anthropic's CLI agent), powered by **Claude Opus 4.6**.

- Human: Robert Supernor — product direction, priorities, review
- AI: Claude Code — implementation, architecture, shell scripting, TypeScript

Every commit includes:
```
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```
