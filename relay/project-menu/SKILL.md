---
name: project-menu
description: Project lifecycle menu. Start projects, manage them, archive them. Context-aware. Usage: /project-menu
version: 2.0.0
author: relay
tags: [project-menu, project, lifecycle, management]
---

# project-menu

The project lifecycle entry point. Behavior depends on where Robert invokes it.

## Execution Ownership

**Relay executes this skill directly.** Do NOT forward to Captain or Scribe for UI rendering.

- **Relay handles**: All Discord UI — buttons, modals, select menus, component interactions
- **Scribe handles**: Backend work — file creation, tracking updates, archiving — dispatched via `sessions_spawn`

If Relay forwards this skill instead of executing it, no interactive UI will render. Relay is the only agent with Discord component access.

## Invoke

```
/project-menu              — context-aware (detects DM, project channel, or archived channel)
/project-menu <name>       — skip topic detection, go straight to project creation for <name>
```

When invoked with a name argument:
- Skip Step 1 (chat scanning) and Step 2 (topic suggestions)
- Use the provided name as the project name
- Go directly to Step 3's goal modal pre-filled with the name

## Context Detection

When `/project-menu` is invoked, detect where Robert is:

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

b. **Initialize tracking files** — dispatch to Scribe via `sessions_spawn`:
```json
{
  "tool": "sessions_spawn",
  "params": {
    "task": "Initialize project tracking for <name>. Goal: <goal from modal>. Create decisions/<name>.md and projects/<name>.md in workspace.",
    "agentId": "spec-projects",
    "label": "project-menu:init"
  }
}
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
"Head to #<channel-name> to start working. Type /project-menu there anytime to see your options."

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

### On selection — Relay UI + Scribe backend via `sessions_spawn`:

| Selection | Relay (UI) | Scribe (backend via `sessions_spawn`) |
|-----------|-----------|---------------------------------------|
| `status` | Display formatted result | `task: "Get project status for #<channel>", label: "project-menu:status"` |
| `plan-create` | Display plan card with approve/modify buttons | `task: "Create phased plan for #<channel>. Topic: <topic>", label: "project-menu:plan"` |
| `task-add` | Show task modal, collect input | `task: "Add task '<title>' assigned to <assignee> in #<channel>", label: "project-menu:task-add"` |
| `decide` | Show decision modal, collect input | `task: "Log decision in #<channel>: <text>, status: <status>", label: "project-menu:decide"` |
| `decisions` | Display formatted decision board | `task: "Get decision board for #<channel>", label: "project-menu:decisions"` |
| `context-audit` | Display audit results | `task: "Run context/token audit for #<channel>", label: "project-menu:context-audit"` |
| `archive` | Show archive confirmation buttons | On confirm: `task: "Archive project #<channel>", label: "project-menu:archive"` |

All `sessions_spawn` calls use `agentId: "spec-projects"`.

### Task modal:

Before rendering, query `skill-router.sh list` for the current agent roster to populate the assignee dropdown dynamically. Exclude Relay from assignee options (Relay is UI-only, not a task executor).

Fall back to the static list below if the router is unavailable:

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

The static list is a fallback only. Always prefer the dynamic roster.

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

Reply with a simple text message: "No problem. The history is all here. Type /project-menu if you change your mind."

Do not create a session. Do not process further messages as tasks.

---

## Proactive Archive Suggestion

Trigger this when either condition is met:
- Scribe reports ALL tasks done AND ALL decisions resolved for a project channel
- Any `sessions_spawn` result from Scribe contains "all tasks complete" or equivalent

When triggered, proactively suggest archiving:

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

Relay dispatches backend tasks to Scribe via `sessions_spawn`. Skip Captain for `/project-menu` actions to save tokens.

```json
{
  "tool": "sessions_spawn",
  "params": {
    "task": "<descriptive task for Scribe>",
    "agentId": "spec-projects",
    "label": "project-menu:<action>"
  }
}
```

Relay handles ALL Discord UI rendering. Scribe never renders components.

## Error Handling

| Scenario | Relay Action |
|----------|-------------|
| `shared-config.json` missing or unreadable | Inform Robert: "Config file missing — can't detect channel context." Offer button: "Notify Captain" |
| Channel creation fails | Show error with buttons: "Retry" / "Use different name" |
| Scribe `sessions_spawn` fails or times out | Show warning: "Backend task didn't complete." Buttons: "Retry" / "Skip" |
| Robert abandons mid-flow (no response) | Do NOT continue prompting. Start fresh on next `/project-menu` invocation |
| Permission error (bot lacks Discord permissions) | Tell Robert which permission is needed (e.g., "Bot needs Manage Channels in the Projects category") |

## Rules

- /project-menu is the ONLY project command Robert needs to know
- Always use Discord components (buttons, selects, modals) — never plain text menus
- Detect context first — never ask Robert where he is
- Skip Captain routing for /project-menu dispatches — Relay talks to Scribe directly
- Keep the select menu options to 7 or fewer — cognitive overload defeats the purpose
- After every action, remind Robert: "Type /project-menu for more options" (but not annoyingly)
- On archive: CLOSE session, do NOT delete. Keep data for reactivation.
- On reactivate: restore context from pinned decisions + project file, do not start blank
