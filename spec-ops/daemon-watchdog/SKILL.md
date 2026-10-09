---
name: daemon-watchdog
description: Check all host-side daemons are running and healthy. Auto-restart what can be restarted, alert on what can't. Run on heartbeat or /daemon-status.
version: 1.0.0
author: ops-officer
tags:
  - daemons
  - health
  - watchdog
  - infrastructure
  - tap
  - backbone
  - executor
trigger:
  command: /daemon-status
  keywords:
    - daemon health
    - daemon status
    - process check
    - tap status
    - backbone status
    - executor status
---

# daemon-watchdog

Check all host-side daemons and report status. Auto-restart recoverable processes.

## Monitored daemons

| Daemon | Process match | Auto-restart | Owner |
|--------|--------------|--------------|-------|
| Tap daemon | `python3 tap-daemon.py` | Yes | Ops Officer |
| host-ops-executor | `host-ops-executor` | No (systemd) | Ops Officer |
| backbone-listener | `backbone-listener.py` | Yes | Ops Officer |
| relay-handoff-watcher | `relay-handoff-watcher.py` | Yes | Ops Officer |
| telegram-listener | `telegram-listener.py` | Yes (cron) | Ops Officer |
| Bridge dashboard (main) | `bridge/dashboard-api.py` | Alert only | Ops Officer |
| Bridge dashboard (dev) | `bridge-dev/dashboard-api.py` | Alert only | Ops Officer |
| Bridge dashboard (corinne) | `bridge-corinne/dashboard-api.py` | Alert only | Ops Officer |
| Ollama | `ollama serve` | Alert only | Ops Officer |
| Gateway container | `openclaw-gateway` | Yes (stability-monitor) | Ops Officer |

## Procedure

1. Run the check:
   ```bash
   echo "=== Daemon Watchdog ===" && \
   for proc in "python3 tap-daemon.py:Tap" "host-ops-executor:Executor" "backbone-listener.py:Backbone" "relay-handoff-watcher.py:Handoff Watcher" "telegram-listener.py:Telegram Listener" "ollama serve:Ollama"; do
     NAME="${proc#*:}"; PATTERN="${proc%%:*}"
     if ps aux | grep "[$( echo "$PATTERN" | cut -c1)]$(echo "$PATTERN" | cut -c2-)" | grep -qv grep 2>/dev/null; then
       echo "  ✅ $NAME"
     else
       echo "  ❌ $NAME — DOWN"
     fi
   done && \
   for BRIDGE in bridge bridge-dev bridge-corinne; do
     if ps aux | grep "[d]ashboard-api.py" | grep -q "$BRIDGE"; then
       echo "  ✅ Bridge ($BRIDGE)"
     else
       echo "  ❌ Bridge ($BRIDGE) — DOWN"
     fi
   done
   ```

2. For machine-readable output (agent-compatible):
   ```bash
   python3 -c "
   import subprocess, json
   daemons = {
     'tap': 'python3 tap-daemon.py',
     'executor': 'host-ops-executor',
     'backbone': 'backbone-listener.py',
     'handoff_watcher': 'relay-handoff-watcher.py',
     'telegram_listener': 'telegram-listener.py',
     'ollama': 'ollama serve',
   }
   result = {}
   for name, pattern in daemons.items():
     r = subprocess.run(['pgrep', '-f', pattern], capture_output=True)
     result[name] = 'up' if r.returncode == 0 else 'down'
   print(json.dumps(result))
   "
   ```

## On heartbeat

Run the quick check. If any daemon is down:
1. Attempt auto-restart for recoverable daemons
2. If restart fails, create an ops.db task with urgency=critical
3. Alert via Discord ops channel (never Telegram — daemon failures are routine ops)

## Escalation

- 1 restart attempt per 5-minute cycle (stability-monitor handles this)
- If same daemon fails 3 times in 15 minutes, escalate to Robert via Telegram
- Chart the failure pattern

## Important

- Use `ps aux | grep "[f]irst-char-bracket-trick"` pattern — NOT `pgrep -f`
- `pgrep -f` has false positives when Claude Code sessions are running (CC bash wrappers contain process names as strings)
- stability-monitor.sh is the automated enforcement; this skill is for on-demand checks and agent awareness
