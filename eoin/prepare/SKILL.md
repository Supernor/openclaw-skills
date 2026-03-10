---
name: prepare
description: Preparation check — am I ready for what Corinne will do next? Reviews memory, prefs, onboarding status, and known gaps. Reports readiness and flags what needs attention.
version: 1.0.0
author: eoin
tags: [prepare, readiness, onboarding, anticipate, check-in]
---

# prepare

## Purpose

Self-assessment: "Am I prepared for what Corinne will do next?"

Run this skill to audit your own readiness. It checks what you know, what you're missing, and what Corinne is likely to need soon. Use it:
- Before a check-in with Corinne
- After learning something new about her
- When you're unsure if you're ready for her next message
- Periodically, to stay sharp

## How It Works

### Step 1: Read Current State
Read these files (skip any that don't exist yet):
- `memory/corinne-prefs.md` — her preferences, vocabulary map, onboarding checklist
- `USER.md` — who she is, her domains, what matters to her
- `SOUL.md` — your communication guidelines, trust ladder stage

### Step 2: Assess Readiness

Check each area and score it:

**Identity Knowledge** (do I know who she is?)
- [ ] Her preferred name — do I know it?
- [ ] Her communication style preference — do I know it?
- [ ] Her current scaffolding level — is it calibrated?
- [ ] Her expertise areas — can I avoid over-explaining?

**Anticipation** (do I know what she'll ask next?)
- [ ] Her stated goals — do I have them?
- [ ] Her likely next ask — can I guess it?
- [ ] Her current projects — am I tracking them?
- [ ] Her blockers — do I know what's frustrating her?

**Capability** (can I deliver what she needs?)
- [ ] Can I handle her likely next request with my current skills?
- [ ] If not, do I know who to route to?
- [ ] Is the escalation path to Robert clear?
- [ ] Are my tools working? (Helm, Captain, Chartroom)

**Trust Ladder** (am I communicating at the right level?)
- [ ] Current stage matches her actual behavior?
- [ ] Vocabulary map up to date?
- [ ] Any regression signals I missed?

### Step 3: Report

Format a readiness report. If running internally (self-check), log to memory. If Corinne or Robert asks, format for their communication stage.

**Internal format:**
```
## Preparation Check — [date]
Readiness: [HIGH/MEDIUM/LOW]
Gaps: [list what's missing]
Next likely ask: [prediction]
Action needed: [what to do before next interaction]
```

**If LOW readiness on a critical gap:**
Escalate to Robert via bearings: "I'm missing [X] about Corinne and it might affect her experience. Can you fill me in?"

## Onboarding Mode (active until first PTV interview complete)

During onboarding, this skill has extra checks:
- Has she completed each onboarding step? (check the checklist in corinne-prefs.md)
- What's the next onboarding step she should do?
- Is there anything I should proactively offer based on what I know?
- What data should I capture from this interaction for future onboarding design?

### Onboarding Data Capture

Every interaction during onboarding is a data point for improving future human onboarding. After each significant exchange, note:
- What she asked (in her words)
- What she expected vs what happened
- What confused her (if anything)
- What delighted her (if anything)
- How long it took to resolve
- What I needed from Robert to help her

Store these observations in `memory/onboarding-log.md` — this becomes the playbook for onboarding the next human.

## Escalation to Robert

When you hit a gap you can't fill yourself:
1. Use bearings to queue a question for Robert
2. Frame it in system language (Robert is Stage 2-3, compressed)
3. Include: what you need, why, and what Corinne's experience will be if you don't get it
4. Continue serving Corinne with what you have — don't block on Robert's response

## Customization

This skill reads from your memory files. To change what it checks:
- Add items to `corinne-prefs.md` checklists
- Update `USER.md` with new domain knowledge
- The skill adapts automatically — no code changes needed
