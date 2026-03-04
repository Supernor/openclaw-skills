---
name: plan
description: Discord-native project planning with phased execution, approval gates, and live progress tracking. Usage: /plan <description> or /plan <subcommand>
version: 1.0.0
author: scribe
tags: [plan, planning, project, phases, approval]
---

# plan

## Invoke

```
/plan <description>              # Create a plan and enter planning mode
/plan status [plan-id]           # Show active plan progress
/plan approve [plan-id]          # Approve pending plan
/plan modify <changes>           # Request modifications to active plan
/plan pause [plan-id]            # Pause execution
/plan resume [plan-id]           # Resume paused plan
/plan list                       # Show all plans
/plan archive <plan-id>          # Archive completed plan
```

## Script

All operations go through:
```bash
/home/node/.openclaw/scripts/plan-manager.sh <action> [args]
```

## Steps — Creating a Plan (`/plan <description>`)

### 1. Create the plan

```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" create "<description>" --agent spec-projects --channel "<channel-id>" --channel-name "<channel-name>"
```

Save the returned `id` — you'll use it for all subsequent commands.

### 2. Post the Planning Card to Discord

Generate the card JSON:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" card "<plan-id>"
```

Post the embed + components to the channel. The card JSON contains `embed` and `components` fields ready for Discord's message format.

### 3. Create a Discussion Thread

Create a thread on the planning card message named: `📋 Plan: <title>`

Store the thread ID:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" set-thread "<plan-id>" "<thread-id>"
bash "$HOME/.openclaw/scripts/plan-manager.sh" set-message "<plan-id>" "<message-id>"
```

### 4. Recall Existing Decisions

**Before any research, check what Robert has already decided for this channel.**

```bash
cat "$HOME/.openclaw/workspace-spec-projects/decisions/<channel-name>.md" 2>/dev/null
```

If the file exists, extract all DONE and UNDECIDED decisions. These are constraints — do NOT re-ask questions Robert already answered. Log each relevant decision as research:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" add-research "<plan-id>" "Prior decision: <summary>"
```

Also check project metadata if it exists:
```bash
cat "$HOME/.openclaw/workspace-spec-projects/projects/<channel-name>.md" 2>/dev/null
```

### 5. Research Phase (READ-ONLY)

**CRITICAL: During research, you may ONLY read files, query data, and search. You must NOT modify any files, configs, or resources.**

Explore the problem space:
- Read relevant files, configs, existing infrastructure
- Check what already exists that could be reused
- Identify dependencies and constraints
- Note potential approaches

Log each finding:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" add-research "<plan-id>" "<finding>"
```

Update the card after research to show findings:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" card "<plan-id>"
```
Edit the original card message with the updated embed.

### 6. Build the Plan

Create phases:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" add-phase "<plan-id>" "Foundation"
bash "$HOME/.openclaw/scripts/plan-manager.sh" add-phase "<plan-id>" "Integration" --gate
bash "$HOME/.openclaw/scripts/plan-manager.sh" add-phase "<plan-id>" "Polish"
```

Add steps to each phase:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" add-step "<plan-id>" 1 "Create notification templates"
bash "$HOME/.openclaw/scripts/plan-manager.sh" add-step "<plan-id>" 1 "Build sender script"
bash "$HOME/.openclaw/scripts/plan-manager.sh" add-step "<plan-id>" 2 "Hook into existing system"
```

### 7. Add Decision Polls (if alternatives exist)

When there are multiple valid approaches:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" add-decision "<plan-id>" "How should notifications be delivered?" --options "Webhook to #ops-alerts,DM to Robert,New dedicated channel,Thread per incident"
```

Post the decision as a Discord poll in the plan thread.

### 8. Present the Plan

Mark the plan ready:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" set-ready "<plan-id>"
```

Generate and post the full plan card:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" card "<plan-id>"
```

Edit the original card message with the ready-state card (yellow, with Approve/Modify/Reject buttons).

### 9. Wait for Approval

The plan is now waiting for Robert. He can:
- **Approve** → triggers execution
- **Modify** → sends change text, plan re-enters planning mode
- **Reject** → plan is archived with reason

## Steps — Executing a Plan (after approval)

### 1. On Approval

When `plan-approve-<id>` button is clicked:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" approve "<plan-id>"
```

Update the card to green executing state. Begin Phase 1.

### 2. Execute Steps

For each step in the active phase:

a. Mark step active:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" step-active "<plan-id>" "<step-id>"
```

b. **Do the work.** (Now you CAN modify files, create resources, etc.)

c. Mark step done:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" step-done "<plan-id>" "<step-id>"
```

d. Update the card with progress:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" card "<plan-id>"
```

### 3. Phase Transitions

When all steps in a phase are done, advance:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" advance "<plan-id>"
```

If the next phase has `gate: true`, the plan enters `gate` status and Robert is prompted to continue. Update the card to show the gate check.

### 4. Completion

When all phases are done:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" complete "<plan-id>"
```

Update the card to the completion state with full summary.

## Steps — Sub-commands

### `/plan status [plan-id]`

```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" status "<plan-id>"
```

If no plan-id given, check for the most recent active plan:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" list --active
```

Format the status output as a Discord embed and post it.

### `/plan approve [plan-id]`

Same as clicking the Approve button:
```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" approve "<plan-id>"
```

### `/plan modify <changes>`

```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" modify "<plan-id>" "<changes>"
```

Re-enter planning mode. Revise the plan based on the modification, then re-present.

### `/plan pause [plan-id]`

```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" pause "<plan-id>"
```

Update card to paused state.

### `/plan resume [plan-id]`

```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" resume "<plan-id>"
```

Update card to executing state. Continue from where execution left off.

### `/plan list`

```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" list --active
```

Format as a compact list:
```
RESULT: Active Plans

📋 mhn-2026-03-02 — Model Health Notifications (executing, 5/9 55%)
📋 auth-abc1 — Add Authentication (planning)

STATUS: success
```

### `/plan archive <plan-id>`

```bash
bash "$HOME/.openclaw/scripts/plan-manager.sh" archive "<plan-id>"
```

## Agent Behavior Rules

### During Planning Status
- **CAN:** Read files, query data, search repos, gather context, build plan structure
- **CANNOT:** Modify files, change configs, create/delete resources, run destructive commands
- **MUST:** Log all research findings via `add-research`
- **MUST:** Update the card after research findings are gathered

### During Executing Status
- **CAN:** Full agent capabilities — read, write, create, modify
- **MUST:** Mark each step active before starting work
- **MUST:** Mark each step done after completing work
- **MUST:** Update the card after each step completion
- **MUST:** Advance phases when all steps in a phase are done
- **SHOULD:** Post progress updates in the plan thread

### During Gate Status
- **CANNOT:** Proceed to next phase without Robert's approval
- **MUST:** Present what was accomplished in the completed phase
- **MUST:** Wait for Continue/Revise/Stop button click

### Cross-Agent Awareness
When a plan involves multiple agents:
- Captain tags related tasks with the plan-id
- Each agent marks their steps done via `plan-manager.sh step-done`
- Scribe (spec-projects) is the default plan owner
- Other agents are workers — they execute assigned steps

## Card Update Pattern

After any state change, always:
1. Run `plan-manager.sh card <plan-id>` to get updated card JSON
2. Edit the original Discord message with the new embed + components
3. If it's a major state change (approved, phase complete, gate reached), also post a notification in the thread

## Storage

Plans stored in `~/.openclaw/plans/<plan-id>.json` — managed exclusively by the script.
Archived plans move to `~/.openclaw/plans/archive/`.

## Rules
- Always use the script — never edit plan JSON directly
- One card per plan — edit in place, never recreate
- Thread for all discussion — keep the main channel clean
- Update card on every step completion — Robert should see live progress
- Research findings logged before plan is built — show your work
- If no plan-id specified on sub-commands, use the most recent active plan
