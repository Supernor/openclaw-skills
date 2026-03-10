---
name: prepare
description: Preparation check — am I ready for what Robert will do next? Reviews memory, prefs, active projects, and known gaps. Reports readiness and flags what needs attention.
version: 1.0.0
author: relay
tags: [prepare, readiness, anticipate, check-in]
---

# prepare

## Purpose

Self-assessment: "Am I prepared for what Robert will do next?"

Run this to audit your own readiness. Checks what you know, what you're missing, and what Robert is likely to need soon. Use it:
- Before a check-in with Robert
- After a long gap between interactions
- When system state has changed significantly
- Periodically, to stay sharp

## How It Works

### Step 1: Read Current State
- `memory/robert-prefs.md` — his preferences, routing rules, execution style
- `USER.md` — who he is, his domains
- `SOUL.md` — communication guidelines, trust ladder stage

### Step 2: Assess Readiness

**Anticipation** (do I know what he'll ask next?)
- [ ] His active projects — am I tracking them?
- [ ] His stated priorities — do I have them?
- [ ] His likely next ask — can I predict it?
- [ ] Recent system changes — can I brief him if asked?

**Capability** (can I deliver?)
- [ ] Can I handle his likely next request with my current skills?
- [ ] Fleet health — any agents down or degraded?
- [ ] Helm engines — all available?
- [ ] Chartroom — accessible and current?

**Trust Ladder** (am I at the right level?)
- [ ] Communicating at Stage 2-3 (compressed, Robert's level)?
- [ ] Vocabulary map current? ("proud", "the mission", "something's off")
- [ ] Not over-explaining things he already knows?

### Step 3: Report

**Internal format:**
```
## Preparation Check — [date]
Readiness: [HIGH/MEDIUM/LOW]
Gaps: [list what's missing]
Next likely ask: [prediction]
Action needed: [what to do before next interaction]
```

**If Robert asks:** Brief, compressed. "Fleet's healthy. Three active projects. You'll probably ask about [X] — ready for it."

## Corinne Coordination Mode

When Corinne is actively onboarding:
- Track what Eoin is handling vs what needs Robert
- Anticipate Robert asking "how's Corinne's onboarding going?"
- Have a ready summary of: her progress, what Eoin needs, any escalations pending

## Customization

Reads from your memory files. Add items to `robert-prefs.md` or update `USER.md` to change what it checks. No code changes needed.
