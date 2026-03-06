---
name: reactor-incident-recovery
description: Diagnose and guide recovery of stuck, failed, or orphaned Reactor tasks
tags: [reactor, incident, recovery, stuck, failed, troubleshooting]
version: 1.0.0
---

# Reactor Incident Recovery

Diagnose Reactor incidents and guide recovery actions.

## When to use
- "A reactor task is stuck"
- "The reactor failed — what happened?"
- "Task X has been running too long"
- "The reactor service is down"
- "Clean up a failed task"
- "Why did the reactor timeout?"

## Required Inputs
- **task-id** (for specific task recovery)
- **symptom description** (for general diagnosis)

## Incident Types

### 1. Stuck Task (in-progress > 15min)
**Detect:**
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh status
# Look for in-progress count > 0 with old timestamps
sqlite3 ~/.openclaw/bridge/reactor-ledger.sqlite \
  "SELECT task_id, subject, date_started FROM jobs WHERE status='in-progress' AND datetime(date_started) < datetime('now', '-15 minutes');"
```

**Diagnose:**
- Check if claude process is still running: `ps aux | grep 'claude -p'`
- Check reactor logs: `tail -50 /root/.openclaw/logs/reactor.log`
- Check systemd status: `systemctl status openclaw-reactor.service`

**Recommend to Captain:**
1. If claude process is hanging: bridge-reactor.sh force-fail guard should catch it (10min timeout) — wait or escalate
2. If systemd service is stopped: recommend `systemctl restart openclaw-reactor.service` to ops
3. If task is truly orphaned (no process, still in-progress): recommend force-fail via bridge-reactor.sh to ops

### 2. Failed Task
**Detect:**
```bash
bash ~/.openclaw/scripts/reactor-ledger.sh task <task-id>
# Check exit_code and result_preview
```

**Diagnose:**
- Exit code 0 but status=failed: Check result_preview for clarification questions
- Exit code non-zero: Check reactor.log around the timestamp
- Duration < 5s with failure: Likely a prompt/permission/config issue, not a real task failure

**Recommend to Captain:**
1. Read the result_preview for error details
2. Check if it's a clarification question (return to requesting agent with context)
3. If infrastructure issue: recommend fix and re-queue to the requesting agent
4. If task scope issue: advise splitting or re-scoping

### 3. Service Down
**Detect:**
```bash
systemctl is-active openclaw-reactor.service
journalctl -u openclaw-reactor.service --since "5 minutes ago" --no-pager
```

**Recommend to Captain:**
1. Check journal for crash reason
2. Recommend `systemctl restart openclaw-reactor.service` to ops
3. After restart, verify inbox processing resumes
4. Check for any tasks that were in-progress when service died (force-fail guard should have caught them)

### 4. Timeout (inactivity)
**Detect:**
```bash
grep "TIMEOUT" /root/.openclaw/logs/reactor.log | tail -5
```

**Diagnose:**
- Task required human input (can't in -p mode)
- Task scope too large (>10min of work)
- External service unreachable (network issue)

**Recommend to Captain:**
1. Check the result — timeout still writes partial results
2. If scope issue: recommend re-scoping and splitting into smaller tasks
3. If external dependency: recommend fixing dependency first, then re-queue

## Expected Output

```
Incident Report: <task-id>
- Type: stuck / failed / timeout / service-down
- Detected: <timestamp>
- Cause: <diagnosis>
- Impact: <what's blocked>
- Recovery: <specific steps>
- Status: RECOVERED / NEEDS_ACTION
```

## Safety Constraints & Escalation Boundaries
- **Do NOT restart systemd services directly** — report the need and let ops confirm
- **Do NOT manually edit the ledger** — only read from it; modifications go through bridge-reactor.sh
- **Do NOT re-queue tasks** — that's the requesting agent's job. Only diagnose and advise.
- **Do NOT execute recovery actions** — diagnose and produce an actionable report for Captain
- Escalate to Captain if recovery requires infra changes, service restarts, or ledger corrections
- Always search Chartroom (`memory_recall error reactor`) before diagnosing from scratch

Your role is diagnosis + recommendation. Execution belongs to Dev (tasks), Repo-Man (infra), or ops (service restarts).
