---
name: plan
description: Unified project lifecycle command. Start projects, manage them, archive them. Context-aware — behavior changes based on where you invoke it. Usage: /plan
version: 2.0.0
author: relay
tags: [plan, project, lifecycle, management]
---

# plan

The single entry point for all project work. Behavior depends on where Robert invokes it.

## Invoke

```
/plan
```

That's it. No arguments, no subcommands. Context does the rest.

## Context Detection

When `/plan` is invoked, detect where Robert is:

### 1. Read shared-config.json

```bash
cat /home/node/.openclaw/shared-config.json
```

Get `categories.projects` and `categories.archives` IDs.

### 2. Determine current channel context

Use `channel-info` on the current channel to get its `parentId` (category).

- **Channel is in Projects category** → Show PROJECT MENU
- **Channel is in Archives category** → Show REACTIVATE PROMPT
- **Channel is a DM or any other channel** → Show NEW PROJECT FLOW

---

## Flow A: NEW PROJECT (DM or non-project channel)

### Step 1: Scan recent chat

Read the last 50 messages in the current channel using `readMessages`.

Analyze the conversation for distinct topics, problems, or project ideas being discussed.

### Step 2: Present topic suggestions

Post a message with buttons for each detected topic (max 4), plus "Something else":

```json
{
  "components": {
    "text": "Looks like you've been discussing a few things. Start a project?",
    "blocks": [{
      "type": "actions",
      "buttons": [
        { "label": "<Topic 1 - short>", "style": "primary" },
        { "label": "<Topic 2 - short>", "style": "secondary" },
        { "label": "Something else", "style": "secondary" }
      ]
    }]
  }
}
```

If chat history is empty or unclear:

```json
{
  "components": {
    "text": "What do you want to build?",
    "modal": {
      "title": "New Project",
      "triggerLabel": "Describe it",
      "triggerStyle": "primary",
      "fields": [
        { "type": "text", "name": "name", "label": "Project name (short, lowercase, hyphens)", "required": true },
        { "type": "text", "name": "goal", "label": "What should it do when it's done?", "required": true, "style": "paragraph" },
        { "type": "text", "name": "constraints", "label": "Any constraints or preferences?", "required": false, "style": "paragraph" }
      ]
    }
  }
}
```

### Step 3: On topic selection

When Robert clicks a topic button, open a modal to refine:

```json
{
  "components": {
    "text": "Good choice. Let me get a few details.",
    "modal": {
      "title": "Project: <topic>",
      "triggerLabel": "Fill in details",
      "triggerStyle": "primary",
      "fields": [
        { "type": "text", "name": "name", "label": "Channel name (short, lowercase, hyphens)", "required": true },
        { "type": "text", "name": "goal", "label": "What does done look like?", "required": true, "style": "paragraph" }
      ]
    }
  }
}
```

### Step 4: Create the project

Using the modal response:

a. **Create Discord channel** in Projects category:
Use `channel-create` with:
- `guildId`: from shared-config
- `parentId`: categories.projects from shared-config
- `name`: from modal
- `type`: 0 (text)

b. **Initialize tracking files** — dispatch to Scribe (spec-projects) via agent-send:
```
TASK: Initialize project tracking for <name>
CONTEXT: Goal: <goal from modal>. Create decisions/<name>.md and projects/<name>.md in workspace.
CHANNEL: <new channel name>
```

c. **Post initial scope card** in the new channel:

```json
{
  "components": {
    "text": "**Project: <name>**\n\n**Goal:** <goal>\n\n**Features:**\n✅ Approved: (none yet)\n🤔 Considering: (none yet)\n🚫 Won't work: (none yet)\n📌 Later: (none yet)\n\nLet me ask a few questions to build the scope.",
    "blocks": [{
      "type": "actions",
      "buttons": [
        { "label": "Looks good, start planning", "style": "success" },
        { "label": "I want to add more context", "style": "secondary" }
      ]
    }]
  }
}
```

d. **Ask scoping questions** — based on the goal, ask 2-3 targeted questions using buttons or modals. Focus on:
- What is the minimum viable version?
- Are there things this should NOT do?
- Any deadline or budget constraint?

e. **Update scope card** with answers, categorizing features into the four tiers.

f. **Tell Robert where to go:**
"Head to #<channel-name> to start working. Type /plan there anytime to see your options."

---

## Flow B: PROJECT MENU (in an active project channel)

Post a select menu with all project management options:

```json
{
  "components": {
    "text": "**#<channel-name>** — What do you need?",
    "blocks": [{
      "type": "actions",
      "select": {
        "type": "string",
        "placeholder": "Pick an action",
        "options": [
          { "label": "Project Status", "value": "status", "description": "Health check — decisions, tasks, progress" },
          { "label": "Start Planning", "value": "plan-create", "description": "Build a phased execution plan" },
          { "label": "Add Task", "value": "task-add", "description": "Add a task to the board" },
          { "label": "Log Decision", "value": "decide", "description": "Record a decision with rationale" },
          { "label": "View Decisions", "value": "decisions", "description": "Show the decision board" },
          { "label": "Context Check", "value": "context-audit", "description": "Token efficiency audit" },
          { "label": "Archive Project", "value": "archive", "description": "Mark complete and archive" }
        ]
      }
    }]
  }
}
```

### On selection, dispatch to the right skill:

| Selection | Action |
|-----------|--------|
| `status` | Dispatch to Scribe: `/status` for this channel |
| `plan-create` | Dispatch to Scribe: `/plan <channel topic>` to start phased planning |
| `task-add` | Show modal with task title + optional assignee, then dispatch to Scribe: `/task add <title>` |
| `decide` | Show modal with decision text + status (select: DONE/UNDECIDED/SAVE-FOR-LATER/WONT-WORK), then dispatch to Scribe: `/decide <status> <text>` |
| `decisions` | Dispatch to Scribe: `/decisions` |
| `context-audit` | Dispatch to Scribe: `/project-audit context` |
| `archive` | Trigger archive confirmation flow (see below) |

### Task modal:

```json
{
  "components": {
    "modal": {
      "title": "Add Task",
      "triggerLabel": "Add",
      "fields": [
        { "type": "text", "name": "title", "label": "What needs to be done?", "required": true },
        { "type": "select", "label": "Assign to", "options": [
          { "label": "Unassigned", "value": "none" },
          { "label": "Dev", "value": "spec-dev" },
          { "label": "Repo-Man", "value": "spec-github" },
          { "label": "Scribe", "value": "spec-projects" }
        ]}
      ]
    }
  }
}
```

### Decision modal:

```json
{
  "components": {
    "modal": {
      "title": "Log Decision",
      "triggerLabel": "Log",
      "fields": [
        { "type": "text", "name": "text", "label": "What was decided?", "required": true, "style": "paragraph" },
        { "type": "select", "label": "Status", "options": [
          { "label": "Done - decided and implemented", "value": "DONE" },
          { "label": "Undecided - needs more thought", "value": "UNDECIDED" },
          { "label": "Save for later", "value": "SAVE-FOR-LATER" },
          { "label": "Won't work", "value": "WONT-WORK" }
        ]}
      ]
    }
  }
}
```

### Archive confirmation:

```json
{
  "components": {
    "text": "Archive **#<channel-name>**?\n\nThis will:\n- Pin the final decision board\n- Move channel to Archive\n- Set channel read-only\n- Close the session (data kept for reactivation)",
    "blocks": [{
      "type": "actions",
      "buttons": [
        { "label": "Archive - Complete", "style": "success" },
        { "label": "Archive - Partial", "style": "secondary" },
        { "label": "Cancel", "style": "danger" }
      ]
    }]
  }
}
```

On "Archive - Complete" or "Archive - Partial": dispatch to Scribe's archive skill.

After archive completes:
- Close the session (do NOT delete — keep data for reactivation)
- Confirm in the channel with a final message

---

## Flow C: REACTIVATE (in an archived channel)

This flow triggers when Robert sends ANY message in a channel that's in the Archives category. Relay should check the channel's category before processing any message.

```json
{
  "components": {
    "text": "This project is archived. Want to reactivate it?",
    "blocks": [{
      "type": "actions",
      "buttons": [
        { "label": "Yes, reactivate", "style": "success" },
        { "label": "No, just browsing", "style": "secondary" }
      ]
    }]
  }
}
```

### On "Yes, reactivate":

a. Move channel back to Projects category:
Use `channel-edit` to set `parentId` to categories.projects from shared-config.

b. Remove read-only permission override (re-enable SEND_MESSAGES for @everyone).

c. Reopen/create session for the channel.

d. Read the pinned decision board and any project file to restore context.

e. Post welcome-back message:

```json
{
  "components": {
    "text": "**#<channel-name>** is active again.\n\nHere's where we left off:\n<summary of last decision board state>\n\nType /plan to see your options.",
    "blocks": [{
      "type": "actions",
      "buttons": [
        { "label": "Continue where I left off", "style": "primary" },
        { "label": "Start fresh", "style": "secondary" }
      ]
    }]
  }
}
```

### On "No, just browsing":

Reply with a simple text message: "No problem. The history is all here. Type /plan if you change your mind."

Do not create a session. Do not process further messages as tasks.

---

## Proactive Archive Suggestion

When Scribe reports all tasks as done for a project channel, Relay should proactively suggest archiving:

```json
{
  "components": {
    "text": "All tasks complete in **#<channel-name>**! Ready to archive?",
    "blocks": [{
      "type": "actions",
      "buttons": [
        { "label": "Archive - Complete", "style": "success" },
        { "label": "Not yet, more to do", "style": "secondary" }
      ]
    }]
  }
}
```

---

## Dispatch Pattern

Relay dispatches to Scribe directly via agent-send for project operations. Skip Captain for /plan actions to save tokens.

```
TASK: <skill-specific task>
CONTEXT: <minimal context>
CHANNEL: <channel name>
SOURCE: relay (Robert via /plan)
```

## Rules

- /plan is the ONLY project command Robert needs to know
- Always use Discord components (buttons, selects, modals) — never plain text menus
- Detect context first — never ask Robert where he is
- Skip Captain routing for /plan dispatches — Relay talks to Scribe directly
- Keep the select menu options to 7 or fewer — cognitive overload defeats the purpose
- After every action, remind Robert: "Type /plan for more options" (but not annoyingly)
- On archive: CLOSE session, do NOT delete. Keep data for reactivation.
- On reactivate: restore context from pinned decisions + project file, do not start blank
