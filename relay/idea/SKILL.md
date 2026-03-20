---
name: idea
description: Guided idea intake via Telegram or Discord. Button-first, typed-fallback. Per-user voice.
version: 1.1.0
author: relay
tags: [idea, intake, capture, project, adaptive-intake-engine]
---

# idea -- Adaptive Intake Engine

## Purpose

Capture raw ideas through a guided, button-first flow that produces structured, outcome-focused idea definitions. Prevents method-leakage. Per-user voice adapts to who is using it without changing depth or structure.

## Design Principles

1. Buttons are the guardrail, not a speed bump. They keep thinking in outcomes. Never auto-skip steps.
2. Per-user voice, not per-user depth. Robert and Corinne get the same structure but different language.
3. Method-leakage is a feature. If tech details appear, redirect to outcome language. Park method hints.
4. Ideas graduate to projects deliberately. Intake produces ideas. Promotion is separate.
5. The system asks: is this still the best way? Methods change fast.

## Per-User Voice

Robert thinks in systems. Questions are direct and compressed.
Corinne thinks in narrative and people. Same questions, different language.

The voice is selected by the --account flag or detected from the Telegram account.

## When to Trigger

- User types /idea in Telegram or Discord
- User says "I have an idea" or "new idea"
- Relay detects ideation language and offers capture

## Flow (10 steps)

1. Capture -- raw idea (text only)
2. Intent -- buttons: Build new / Fix broken / Improve existing / Explore
3. Purpose -- buttons: P01-P05 PTV codes
4. Beneficiary -- buttons: Robert / Corinne / Clients / The System / Everyone
5. Capability -- text only, the core of the idea
6. Constraints -- buttons: Budget / Time / Depends on other work / None
7. Urgency -- buttons: Now / This week / This month / Someday
8. Success -- text only
9. Category -- buttons: Cashflow / Leverage / Educate / Sustain / Product
10. Review -- summary card with Confirm / Edit / Discard

Every step accepts typed text as override. No step is ever skipped.

## Method-Leakage Detection

Method content stored separately as method_hints. User redirected to outcome language.

## Resume

Progress saved after every step. On next invocation with incomplete intake, offers to continue.

## Storage

Ideas saved to ideas table in transcripts.db with full intake metadata.
On completion, exported as markdown to adaptive-project-system/ideas/{idea-id}.md.

## CLI

python3 /root/.openclaw/scripts/intake-engine.py                    # Robert default
python3 /root/.openclaw/scripts/intake-engine.py --account corinne  # Corinne voice
python3 /root/.openclaw/scripts/intake-engine.py --resume           # resume last
python3 /root/.openclaw/scripts/intake-engine.py --list             # show incomplete
python3 /root/.openclaw/scripts/intake-engine.py --export ID        # export to APS

## Rules

- NEVER ask about tech stack, framework, API, or implementation architecture
- Always offer buttons first, accept typed text as override
- NEVER auto-skip steps -- buttons are the thinking tool
- Save progress after every step (resumable)
- Export to APS repo on completion
- Do NOT auto-promote
- Use the right voice for the right person

Intent: Responsive [I04], Competent [I03]. Purpose: P04 System Visibility.
