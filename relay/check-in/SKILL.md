---
name: check-in
description: Alignment check-in with Robert via Discord. Captures intent notes, vision/PTV direction, and functionality feedback. Robert's equivalent of Eoin's onboard skill.
version: 1.0.0
author: relay
tags: [check-in, alignment, vision, intent, feedback, direction, ptv, review]
---

# check-in — Robert Alignment Check

## Purpose

Robert's equivalent of Corinne's onboarding — but compressed to Stage 2-3. Captures ONLY three things from Discord interactions:
1. **Intent notes** — "this agent should be better at X"
2. **Vision/PTV direction** — "new priority" or "this north star is stale"
3. **Functionality notes** — "this should work differently"

System operations (config, infra, debugging) stay in Claude Code — Relay does NOT handle these on Discord.

## When to Trigger

- Robert says "check-in", "what's on my mind", "let's align", "vision check"
- Weekly proactive prompt (if enabled in preferences)
- After a significant system change or project milestone

## The Flow

### Step 1: Open

**Template (Stage 2-3):**
> Check-in time. Three areas — pick what's on your mind:

**Buttons:** `[Intent notes]` `[Vision/PTV]` `[Functionality]` `[All three]`

### Step 2A: Intent Notes

> Which agent or area? Quick hits — "X should be better at Y."

Robert types his observations. For each one:
- Map to specific agent + intent code
- Confirm: "[Agent] → improve [Intent]. Got it?"
- Store in Chartroom as `intent-adjustment-[agent]-[date]`
- Queue bearings self-check if the adjustment is systemic

### Step 2B: Vision/PTV Direction

> PTV codes — anything stale, new, or shifting?

**Show current codes as buttons:**
- `[P01 Financial Health]` `[P02 Marketing]` `[P03 Client Delivery]`
- `[P04 System Visibility]` `[P05 Doing Good]` `[New priority]` `[All good]`

If he picks a code: "What's changed?"
If "New priority": "What's the goal? One line."
If "All good": move on.

Store changes → update `workspace/PTV.md`, chart the change, queue bearings for Corinne validation if it affects her codes.

### Step 2C: Functionality Notes

> Anything that should work differently? Skills, routing, responses — quick hits.

Robert describes. For each:
- Identify the affected component (skill, agent, routing, tool)
- Confirm understanding
- Chart as `functionality-note-[topic]-[date]`
- Flag for implementation in next Claude Code session

### Step 3: Summary

> Check-in captured:
> - **Intents:** [count] notes → [agents affected]
> - **Vision:** [changes or "no changes"]
> - **Functionality:** [count] notes → [components affected]
>
> All logged. Anything else?

**Buttons:** `[That's it]` `[One more thing]`

## Customer Test Mode

If `robert-prefs.md` has `customer_test_mode: true`:
- Override communication to Stage 0 (full explanations, buttons, scaffolding)
- Robert experiences what a new customer would see
- All interactions logged as onboarding test data in `memory/test-mode-log.md`
- Robert says "test mode off" → snap back to Stage 2-3

**Detection phrases:** "test mode on", "test mode", "customer mode", "pretend I'm new"
**Exit phrases:** "test mode off", "normal mode", "back to normal"

## Rules

- Keep it compressed for Robert (Stage 2-3) unless test mode is on
- System operations stay in Claude Code — don't accept infra tasks here
- Every note gets charted — nothing gets lost
- If a vision change affects Corinne, queue bearings for her validation
- Use buttons for everything — Robert prefers clicks over typing
