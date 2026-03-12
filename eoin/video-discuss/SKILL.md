---
name: video-discuss
description: YouTube video analysis and discussion for Corinne. Ingests video, gets leverage analysis from Strategist, presents findings in plain language, drives conversation about ideas.
version: 1.0.0
author: eoin
tags: [video, youtube, discuss, analyze, ideas, conversation]
---

# video-discuss — YouTube Video Discussion (Corinne)

## Purpose

Corinne sends a YouTube URL. You pull the video, get it analyzed, and walk her through what it means for OpenClaw — in her language, at her pace.

## Detection

Match any of these in messages:
- `youtube.com/watch` URLs
- `youtu.be/` short URLs
- Bare 11-character video IDs
- "watch this", "check this out", "what do you think of this video"

## Phase 1: Acknowledge + Trust

1. Acknowledge warmly:
   > "On it — let me pull that video and see what's in it."

2. **Known sources** (@NateBJones): auto-trust 0.9. Say: "Oh, Nate — Robert follows him. Good source."

3. **Unknown sources**: Ask casually:
   > "I don't know this channel yet. How reliable do you think they are? Quick scale — 1 (take with a grain of salt) to 5 (really solid)."

4. Dispatch: `exec video-discuss <url> --trust <level>`

5. Keep her posted on timing:
   > "Got the transcript. Now running it through the strategy team — give me a couple minutes."

## Phase 2: Present Results

Translate the JSON into plain language. No jargon, no agent IDs.

**Template:**
> **[Title]** by [Channel]
>
> **What it's about:** [summary in everyday language]
>
> **The good stuff:**
> - [insight 1 — plain language]
> - [insight 2 — plain language]
>
> **What we could do with this:**
> - [leverage point — explain what it means for the family system]
> - [easy win — "this one's free"]
>
> [X] ideas saved for Robert to look at.

**Buttons:** `[Let's Talk About It]` `[Save & Move On]` `[Not Useful]`

If trust_note exists, show it gently:
> "Quick heads up — this source isn't one we know well, so take the suggestions with a grain of salt."

## Phase 3: Discussion (if Corinne taps "Let's Talk About It")

Present discussion seeds conversationally as numbered picks:
> Which of these sounds interesting?
> 1. [seed rephrased in plain language]
> 2. [seed rephrased in plain language]
> 3. [seed rephrased in plain language]
> (Or just tell me what caught your eye)

- Let her lead — she may have different priorities than the analysis suggests
- If she has ideas, capture them: `exec idea add <id> <title> <desc> <category> --source "<video>" --proposed-by eoin`
- After discussion winds down, summarize what came out of it

**Buttons:** `[Build Something From This]` `[Save For Later]` `[All Done]`

## Phase 4: Wrap Up

If "Save & Move On" or "All Done":
> "Nice find. [X] ideas logged from this one. Robert can review them anytime."

If "Not Useful":
> "No worries — not every video's a winner. Send another anytime."

If "Build Something From This":
> "Got it — I'll flag this for Robert as a priority. Which idea stood out most?"
> Capture her pick, then: `exec idea approve <id>` is Robert-only, so instead note it:
> "Marked it as a top pick. Robert will see it next time he checks the pipeline."

## Rules

- Stage 0 communication — explain everything, no assumptions about technical knowledge
- Never use agent IDs or system jargon with Corinne (say "the strategy team" not "Strategist")
- Trust check is casual, not formal
- If the pipeline fails, keep it light: "Hmm, couldn't grab that one. The video might be private or too short. Want to try another?"
- This skill is self-contained — do NOT route through Captain

Intent: Responsive [I01], Connected [I03]. Purpose: Shared video intelligence via Corinne's interface.
