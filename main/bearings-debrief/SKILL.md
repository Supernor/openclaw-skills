---
name: bearings-debrief
description: Vision holder debrief — walk through pending bearing questions one at a time, record responses
tags: [bearings, debrief, vision, alignment]
intent: Connected [I10], Coherent [I19]
version: 1.0.0
---

# /debrief — Bearings Debrief

Interactive Q&A session with a vision holder. Walk through all pending bearing questions one at a time, record each response.

## When to use
- User says "debrief", "bearings", "answer bearings", or "bearing questions"
- Captain or Relay wants to walk Robert/Corinne through pending questions

## Flow

1. Call `bearings_pending` MCP tool with the user's target (robert/corinne/all)
2. If no pending questions, say so and stop
3. For each question:
   - Show the question number (e.g. "[1/5]"), priority, and template type
   - Show the full question text
   - Show the numbered options
   - Wait for the user to reply with a number (1-4), "skip", or "quit"
   - Call `bearings_respond` MCP tool with the question ID and option number
   - Confirm what was recorded
   - Move to next question
4. At the end, summarize: X answered, Y skipped

## Rules
- Present ONE question at a time. Do not dump all questions at once.
- Keep your own words minimal. The question text IS the content.
- Accept numbers (1, 2, 3, 4), "skip"/"s", or "quit"/"q" as responses.
- If the user gives a freeform answer instead of a number, map it to the closest option and confirm: "That sounds like option 2 (Accept for now). Recording that — correct?"
- Questions marked [ops] are operational priority calls. Questions without [ops] are vision/direction decisions.
- Do NOT add your own opinions about the answers. Record what the human says.
- If target is not specified, default to "robert".

## Example

```
User: debrief

Captain: You have 3 pending bearing questions. Let's go through them.

[1/3] Priority 3 — build_clarification
Reactor needs your input:

Should bearings questions arrive as Discord embeds with buttons, or plain text?

1. Embeds with buttons
2. Plain text (current)
3. Both depending on context
4. Ask me later

Your choice?

User: 2

Captain: Recorded: Plain text (current)

[2/3] Priority 4 — build_clarification
Quartermaster needs your input:

Quartermaster declares Responsive but has no communication skills. Should it be able to reach you directly?

1. Yes, add messaging
2. It routes through Captain
3. Not needed for this role
4. Ask me later

Your choice?

User: it should go through captain like everything else

Captain: That sounds like option 2 (It routes through Captain). Recording that — correct?

User: yes

Captain: Recorded: It routes through Captain

[3/3] ...
```

## MCP Tools Used
- `bearings_pending` — get the question list
- `bearings_respond` — record each answer
- `bearings_status` — optional, show summary after debrief
