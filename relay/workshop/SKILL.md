---
name: workshop
description: Route ideas to The Workshop (Scribe on Telegram). Creates Intake topics for structured intent capture.
version: 1.0.0
author: relay
tags: [workshop, idea, intake, scribe]
---

# workshop -- Route to The Workshop

## Purpose

Route ideas and new work requests to Scribe (spec-projects) for structured intent capture through The Workshop on Telegram. Scribe creates a topic in the Ideas group and runs the full pipeline: Intake -> Shape -> Gauntlet -> Green Light -> Build -> Proof.

## When to Trigger

- User types `/workshop`
- User says "workshop this" or "let's workshop it"
- User describes an idea and you detect ideation language ("I want to be able to...", "what if we...", "new idea:", "we should build...")
- Another agent routes an idea to you for Workshop intake

## Flow

### Step 1: Capture the raw idea

If the user provided idea text with the command (e.g. `/workshop I want real-time agent dashboards`):
- Use that text directly. Skip to Step 2.

If bare `/workshop` with no text:
- Ask: "What's the idea? Drop it in one message — rough is fine."
- Wait for their response.

### Step 2: Create task record (MANDATORY)

Before routing anywhere, create a task in ops.db so the work is visible in Bridge.

Use `exec` or Python to insert directly into SQLite:

```python
import sqlite3
db = sqlite3.connect(os.path.expanduser("~/.openclaw/ops.db"))
db.execute(
    "INSERT INTO tasks (agent, task, context, urgency, status, created_at) VALUES (?, ?, ?, ?, 'pending', datetime('now'))",
    ("spec-projects", "Workshop Intake: {idea title or first 80 chars}", "New idea from {user}: {full idea text}", "routine")
)
db.commit()
db.close()
```

This is NOT optional. No task record = invisible work = broken system.

### Step 3: Route to Scribe

Dispatch to Scribe for Workshop intake using `sessions_spawn`:

```json
{
  "tool": "sessions_spawn",
  "arguments": {
    "agentId": "spec-projects",
    "mode": "run",
    "label": "workshop:intake",
    "message": "New idea from {user name}: {full idea text}\n\nCreate a topic in the Ideas group and begin Workshop intake. Start with Intake stage."
  }
}
```

### Step 4: Confirm to user

Tell the user:
- "Idea sent to Workshop — Scribe is setting up a topic in the Ideas group."
- Include the task ID from Step 2 so they can track it in Bridge.
- If on Discord, include Bridge link: http://187.77.193.174:8082

### Fallback: If Scribe is unreachable

If sessions_spawn to spec-projects fails or times out:
1. Tell the user: "Scribe is unavailable. Running local intake instead."
2. Fall back to the `/idea` skill (which runs intake-engine.py locally).
3. The ops.db task from Step 2 still exists, so the work is visible in Bridge regardless.

### Fallback: If ops.db insert fails

If the SQLite insert fails:
1. Try CLI: `exec workshop-submit.sh "{idea text}" "spec-projects" "routine"`
2. If that also fails, tell the user and log the failure.
3. Still attempt Scribe routing — the idea shouldn't be lost just because ops.db is down.

## Rules

- ALWAYS create the ops.db task record BEFORE routing to Scribe
- NEVER improvise a text-only pseudo-workshop — use the real system
- NEVER skip the task record — invisible work is the #1 system failure
- If both Scribe AND ops.db insert fail, tell the user clearly: "Workshop is down. Your idea: {text}. I'll retry when systems recover."

## Per-User Voice

- **Robert**: "Intake logged. Scribe's on it — topic incoming in Ideas."
- **Corinne**: "Got it! Scribe is setting up a space for this in the Ideas group."

Intent: Responsive [I04], Reliable [I05]. Purpose: P04 System Visibility.
