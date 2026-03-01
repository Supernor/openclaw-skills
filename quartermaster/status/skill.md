---
name: status
description: Project health summary — decisions, tasks, and activity at a glance. Usage: /status [channel]
version: 1.0.0
author: scribe
tags: [status, project, health, dashboard]
---

# status

## Invoke

```
/status                   # Status for current project channel
/status <channel-name>    # Status for a specific project
/projects                 # List all project channels with brief status
```

## Steps

### 1. Gather data

For the target channel:

**Decisions:**
```bash
cat /home/node/.openclaw/workspace-spec-projects/decisions/<channel>.md
```
Count by status: DONE, UNDECIDED, SAVE-FOR-LATER, DECIDED-NOT-DONE, WONT-WORK.

**Tasks:**
```bash
/home/node/.openclaw/scripts/task-manager.sh summary <channel>
```
Returns JSON with counts by status (todo, in-progress, blocked, done), assignees, linked decisions.

**Activity:**
- Check file modification times on both `decisions/<channel>.md` and `tasks/<channel>.json`
- Flag as "stale" if no updates in 7+ days

**Project metadata (if exists):**
```bash
cat /home/node/.openclaw/workspace-spec-projects/projects/<channel>.md
```

### 2. Compute health

| Health | Condition |
|--------|-----------|
| Active | Has in-progress tasks OR updated in last 3 days |
| Healthy | Has tasks/decisions, updated in last 7 days |
| Stale | No updates in 7+ days with open tasks/undecided items |
| Blocked | Has blocked tasks |
| Empty | No tasks and no decisions |

### 3. Format response

```
RESULT: Project status for #<channel>

📊 **#<channel>** — <health>
_Topic: <topic if set>_

📜 Decisions: <done>/<total> resolved
  ✅ <done> DONE · ❓ <undecided> UNDECIDED · 📌 <save> SAVE-FOR-LATER

📋 Tasks: <done>/<total> complete
  📋 <todo> todo · 🔄 <ip> in-progress · 🚫 <blocked> blocked · ✅ <done> done

👥 Assignees: <list or "none">
🔗 Linked: <N> tasks tied to decisions

_Last activity: <relative time>_

STATUS: success
```

**If stale:**
```
⚠️ Stale — no updates in <N> days. <undecided> undecided decisions, <open> open tasks.
```

### 4. For `/projects` (cross-project view)

List all channels that have a decisions or tasks file:

```
RESULT: All projects

📊 **#project-alpha** — Active
  Decisions: 5/7 · Tasks: 3/8 · Last: 2h ago

📊 **#project-beta** — Stale (12 days)
  Decisions: 2/4 · Tasks: 0/3 · Last: 12d ago

📊 **#project-gamma** — Healthy
  Decisions: 1/1 · Tasks: 2/2 · Last: 3d ago

STATUS: success
```

## Rules
- Read-only — never modify decisions or tasks
- If channel has no decisions or tasks, say "Empty — use /decide or /task add to start"
- Use relative times ("2h ago", "3d ago") not ISO timestamps
- Keep output compact — this is a glance view
