---
name: system-health
description: Check system health and show status to Robert. Tiered response — text when healthy, fix buttons when broken.
version: 1.0.0
author: relay
tags: [health, status, monitoring, ops, system]
---

# System Health

## Purpose
Give Robert a quick system health check from Telegram or Discord.
When everything is green, show a compact summary. When something is
broken, show what's wrong with a fix button for each issue.

## When to use
- Robert says "status", "health", "how's the system", "is everything ok"
- Morning briefing wants a health snapshot
- After a deploy, update, or restart to verify everything came back up
- When Robert reports something feels slow or broken

## Steps

### Phase 1: Run the health check

Create an ops.db task to run the golden script on the host:
```
ops_insert_task with host_op: "system-health"
```

The script checks 6 things: gateway health, stability state, disk,
memory, systemd services, and recent task pipeline. It returns JSON.

**Expected output:**
```json
{
  "overall_status": "healthy",
  "event_loop": "degraded max=15016ms",
  "disk": "46G/96G (48%)",
  "memory": "3.5Gi/7.8Gi (44%)",
  "services_ok": true,
  "tasks_24h": "completed|14,cancelled|7",
  "issues": [],
  "timestamp": "2026-05-19T14:48:18Z"
}
```

### Phase 2: Format the response (tiered)

**If overall_status is "healthy":**
Send a compact text summary — no buttons, no noise:
```
All systems green
- Gateway: event loop degraded max=15s (normal under load)
- Disk: 46G/96G (48%)
- Memory: 3.5G/7.8G (44%)
- Services: all active
- Tasks (24h): 14 completed, 7 cancelled
```

**If overall_status is "issues_found":**
Send the summary PLUS one button per issue. Each button label is
the component name, and tapping it creates a reactor task with the
fix_action as the host_op:
```
Issues found:
- openclaw-host-ops: Service inactive — Relay cannot dispatch work
- disk: Disk at 87% — check docker images and logs

[Fix host-ops] [Fix disk]
```

Each button creates an ops.db task:
- "Fix host-ops" → host_op: the fix_action from the issue
- Use reactor-task pattern for anything that needs plan-first approval

## Error diagnosis

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Script returns no output | host-ops-executor not running or crashed | `systemctl status openclaw-host-ops` — restart if dead |
| "db_error" in tasks_24h | ops.db locked by another process | Wait 30s and retry — SQLite lock contention is transient |
| event_loop "unknown" | Gateway container not running or health command changed after update | `docker compose -f /root/openclaw/docker-compose.yml ps` to check container status |
| stability "unknown" | stability-state.json missing — stability-monitor may not be running | Check if stability-monitor cron exists: `crontab -l \| grep stability` |
| Script times out (>30s) | Docker exec is slow — container may be overloaded | Check `docker stats` for CPU/memory pressure |

## Related
- `chart read ref-relay-discord-reference` — Discord formatting for status embeds
- `/morning-briefing` — daily briefing includes health snapshot
- `chart search "stability-monitor"` — how stability state is tracked
- `chart search "infra-audit"` — deeper infrastructure investigation

## Notes
- The golden script runs on the HOST, not inside the container. It needs
  `docker compose exec` to reach the gateway, `systemctl` for services,
  and `sqlite3` for ops.db.
- Event loop degradation (max >5s) is gateway-wide, not Relay-specific.
  Don't alarm Robert about it unless it exceeds 30s.
- The script always exits 0. Issues are reported in the JSON output,
  not via exit codes. This prevents the host-ops handler from marking
  the task as "blocked" when the system has issues to report.

Intent: System observability. Robert manages from his phone.
