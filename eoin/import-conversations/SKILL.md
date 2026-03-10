---
name: import-conversations
description: Import Corinne's ChatGPT conversation history into Eoin's memory. Accepts pasted text, Google Docs links, MD files, or share links. Reflects back what was learned.
version: 1.0.0
author: eoin
tags: [import, chatgpt, conversations, history, context, memory, knowledge, transfer]
---

# import-conversations — ChatGPT History Import

## Purpose

Corinne has 3 weeks of ChatGPT conversations with ideas, use cases, and thinking already formed. These are NOT "files to process" — they're Eoin's head start on understanding her. She should never have to repeat something she already told ChatGPT.

## When to Trigger

- During onboarding (Step 5 of the `onboard` skill)
- Corinne says "I have some old conversations" or "here's what I talked to ChatGPT about"
- Corinne sends a file, link, or pasted text that looks like a conversation export

## Input Formats (accept ALL of these)

### 1. Pasted Text (lowest friction)
She pastes conversation text directly into Telegram.
- Accept it as-is
- Parse the conversation turns (human vs AI)
- Extract her questions, ideas, and conclusions

### 2. Google Docs Link
She shares a Google Doc containing copied conversations.
- Note the link for processing when Google Workspace is wired
- If Google access is available: fetch the doc, parse content
- If not yet wired: acknowledge, store link, process when available

### 3. Markdown Files
She sends .md files (ChatGPT export format).
- Parse the markdown structure
- Identify conversation turns
- Extract key content

### 4. ChatGPT Share Link
She shares a ChatGPT conversation share URL.
- Note: these may not be directly fetchable from server
- Ask her to copy-paste the key parts if the link can't be read
- Offer alternatives: "Can you paste the important parts, or drop it in a Google Doc?"

### 5. Screenshots
She sends screenshots of conversations.
- If OCR is available, extract text
- If not, ask her to type or paste the key points

## Processing Flow

### Step 1: Accept Input
Acknowledge immediately: "Got it — let me read through this."

### Step 2: Parse Content
Extract from the conversation:
- **Her questions** — what she wanted to know
- **Her ideas** — things she proposed or brainstormed
- **Her conclusions** — decisions she reached
- **Her frustrations** — what wasn't working
- **Key topics** — recurring themes across conversations
- **Action items** — things she wanted to do but didn't yet

### Step 3: Reflect Back
Show her what you learned. This is the trust-building moment.

**Template:**
> I've been reading through your conversations. You've been thinking a lot about:
>
> 1. **[Topic]** — [what she explored, in her words]
> 2. **[Topic]** — [her conclusion or open question]
> 3. **[Topic]** — [her idea or frustration]
>
> Did I get the picture right? Anything I missed?

**Buttons:** `[Yes, that's it]` `[You missed something]` `[Let me add more]`

### Step 4: Store in Memory
Save extracted knowledge to `memory/corinne-prefs.md`:
- Update `## Known Interests / Likely First Asks` with discovered topics
- Add new expertise areas if revealed
- Note her thinking patterns and communication style
- Store key ideas she wants to pursue

Create a summary in Chartroom if the content is substantial:
- Chart ID: `corinne-chatgpt-import-[date]`
- Category: `reading`
- Content: key themes, ideas, and conclusions extracted

### Step 5: Connect to Action
After reflecting back, connect what you learned to what you can do:

> Based on what you've been thinking about, I can start working on [specific thing] right now. Or if you want to keep building on [topic], I'm ready for that too.

## Rules

- Use HER words when reflecting back, not system language
- Don't summarize too aggressively — she should recognize her own thinking
- If the import is large, process in chunks and check in between
- Never say "I processed your data" — say "I read through your conversations"
- If something is unclear, ask. Don't guess at her meaning.
- This is a CONVERSATION about her ideas, not a data pipeline

## Escalation

If the import reveals topics that need Robert's input (system capabilities, technical requirements):
- Note them separately
- Queue a bearings question for Robert if needed
- Don't block the import conversation on Robert's answer

## Multiple Imports

She may do this more than once. Each time:
- Merge new knowledge with existing, don't overwrite
- Note what's new vs what confirms existing understanding
- Reflect back only NEW insights, not everything again
