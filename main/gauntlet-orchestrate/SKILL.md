---
name: gauntlet-orchestrate
description: Run the 3-agent Gauntlet debate. Codex (devils advocate) vs Reactor (positive advocate), Scribe mediates. Two rounds, then user decisions.
tags: [workshop, gauntlet, debate, multi-agent]
version: 1.0.0
---

# gauntlet-orchestrate — Multi-Agent Debate

## When to use
When an idea has all 10 fields filled and is ready for the Gauntlet stage.
Triggered by: s:gauntlet:run in Tap, or manual dispatch.

## The Debate (2 rounds, 3 agents)

### Setup
1. Read idea from ideas-registry.json — all 10 fields
2. Build idea context string (title, description, capabilities, constraints, success_test, etc)
3. Set idea stage to "gauntlet"

### Round 1
Run these as 3 ops_insert_task calls (Codex tasks can run back-to-back):

**Task A — Devils Advocate (Codex):**
```
Agent: spec-dev
Prompt: "You are the Devils Advocate. Challenge this idea on 6 dimensions:
1. Problem reality 2. Beneficiary honesty 3. Cost awareness
4. Success test rigor 5. Overlap check 6. Urgency reality
Be specific. Max 300 words.
IDEA: {context}"
```

**Task B — Positive Advocate (Codex, blocked_by A):**
```
Agent: spec-dev
Prompt: "You are the Positive Advocate. Counter each concern with a concrete fix.
IDEA: {context}
DEVILS ADVOCATE SAID: {output from Task A}
For each point: Valid/Invalid because X. Fix: Y. Max 300 words."
```

**Task C — Mediator (Scribe, blocked_by B):**
```
Agent: spec-projects
Prompt: "You are the Mediator. Summarize: which concerns resolved, which open.
IDEA: {context}
DEVILS ADVOCATE: {Task A output}
POSITIVE ADVOCATE: {Task B output}
List open decisions the user must make. Max 200 words."
```

### Round 2 (blocked_by Round 1 mediator)
Same structure, but each agent responds to the full Round 1 transcript.
Codex pushes harder on unresolved items. Reactor proposes fixes. Scribe produces final scorecard.

### User Decisions
After Round 2, Scribe's output becomes a decision menu:
- Each unresolved issue = one decision with button options
- Post to both Telegram topic (via Tap) and Bridge/Feedback
- User resolves each decision via buttons or typed answers

### Completion
When all decisions are resolved:
1. Mark Gauntlet as PASSED
2. Update idea stage to "greenlight"
3. Run workshop-dispatch skill to split into tasks

## Cost
~4 Codex calls + 2 Scribe calls per Gauntlet.
At 3000/week Codex cap: sustainable for 2-3 Gauntlets/day.

## Spec
Full spec: docs/gauntlet-v2-debate.md

## Tools
- ops_insert_task with blocked_by for sequencing
- inbox_check to get debate outputs
- bearings_ask for user decisions
- chart_search for overlap check dimension
