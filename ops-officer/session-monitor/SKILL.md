---
name: session-monitor
description: Check agent context capacity (cognitive load) across all agents. Quick health check for session bloat and overload detection.
version: 1.0.0
author: ops-officer
tags:
  - session
  - context
  - cognitive load
  - agent load
  - memory pressure
  - health
trigger:
  command: /session-monitor
  keywords:
    - session health
    - context usage
    - agent load
    - cognitive load
    - memory pressure
---

# session-monitor

Check agent context capacity (cognitive load) across all agents.

## Procedure

1. Run the snapshot:
   ```bash
   bash /home/node/.openclaw/scripts/agent-load-snapshot.sh
   ```

2. For machine-readable output:
   ```bash
   bash /home/node/.openclaw/scripts/agent-load-snapshot.sh --json
   ```

3. For alerting (exit 1 if any agent overloaded):
   ```bash
   bash /home/node/.openclaw/scripts/agent-load-snapshot.sh --check
   ```

4. If STRAINED (70-85%): note it, monitor on next check
5. If OVERLOADED (85-100%): session-maintenance.sh will auto-reset at next cron
6. If BROKEN (>100%): alert immediately in #ops-alerts

## Thresholds
| Context % | State | Action |
|-----------|-------|--------|
| 0-50% | HEALTHY | None |
| 50-70% | WORKING | None |
| 70-85% | STRAINED | Monitor |
| 85-100% | OVERLOADED | Auto-reset (cron) |
| >100% | BROKEN | Immediate alert |

## Output
Table: agent name, load %, state, model, peak session key.
