---
name: video-discuss
description: >
  YouTube URL handler. Step 1: call exec tool with command "video-discuss <url>".
  Step 2: respond with EXACTLY 3 lines, nothing more:
  Line 1: **{title}** by {channel}.
  Line 2: One single sentence summarizing the summary field. Maximum 25 words. One period. Stop.
  Line 3: What caught your eye? What seemed interesting?
  STOP after line 3. No key_insights. No leverage_points. No easy_wins. No discussion_seeds. No extra text. No rephrasing the question.
  The full JSON is your private cheat sheet for follow-up discussion only.
version: 2.1.0
author: relay
tags: [video, youtube, discuss, analyze, leverage, strategy, ideas, transcript]
---

# video-discuss — YouTube Video Discussion (v2.0)

## Purpose

Robert sends a YouTube URL. You ingest it, get leverage analysis, then drive a **collaborative discussion where Robert leads**. The analysis is YOUR private cheat sheet — never dump it unprompted.

## Detection

Match any of these in user messages:
- `youtube.com/watch` URLs
- `youtu.be/` short URLs
- Bare 11-character video IDs
- "analyze this video", "watch this", "check out this video", "discuss this video"

## Phase 1: Acknowledge + Ingest

When you detect a YouTube URL:

1. **Acknowledge immediately:**
   > Got it — pulling that video now.

2. **Known sources** (@NateBJones): auto-use stored trust level (0.9). No need to ask.

3. **New/unknown sources**: Ask Robert to rate trust using buttons:

   On Telegram:
   ```
   message({ action: "send", channel: "telegram", message: "New source — how much do you trust this?", buttons: [[{ text: "Low (1)", callback_data: "trust_1" }, { text: "Medium (3)", callback_data: "trust_3" }, { text: "High (5)", callback_data: "trust_5" }]] })
   ```

   On Discord:
   ```
   message({ action: "send", channel: "discord", message: "New source — how much do you trust this?", components: [{ type: "buttons", buttons: [{ label: "Low (1)", custom_id: "trust_1", style: "secondary" }, { label: "Medium (3)", custom_id: "trust_3", style: "primary" }, { label: "High (5)", custom_id: "trust_5", style: "success" }] }] })
   ```

   Trust mapping: 1 = 0.2, 2 = 0.4, 3 = 0.6, 4 = 0.8, 5 = 1.0

4. **Dispatch the pipeline — CALL THE EXEC TOOL:**
   Use the `exec` tool (default_api.exec) with the `command` parameter:
   ```json
   { "command": "video-discuss <url> --trust <level>" }
   ```
   For known high-trust:
   ```json
   { "command": "video-discuss <url>" }
   ```

   **IMPORTANT: You MUST call the exec tool. Do NOT try to find or locate the script. Do NOT use find, ls, or which. Just call exec with the command above. The PATH is already configured.**

**Timing:** Full pipeline takes ~90-180 seconds (ingest + analysis). Keep Robert informed:
- "Transcript pulled. Running leverage analysis now..."
- If already cached: "Already in the library — pulling up the analysis now." (instant, $0)

## Phase 2: Open the Discussion (Robert leads)

Parse the JSON response. YOUR RESPONSE MUST BE EXACTLY THIS FORMAT — nothing more:

> **[Title]** by [Channel].
> [1-sentence summary — condense the "summary" field to ONE sentence max]
>
> What caught your eye? What seemed interesting?

STOP. Do not add key_insights. Do not add leverage_points. Do not add easy_wins. Do not add discussion_seeds. Do not add a "discussion starter" or "strongest takeaway." ONE sentence from the summary field, then ask Robert. That is your ENTIRE response.

The rest of the JSON is YOUR PRIVATE CHEAT SHEET for Phase 3. You share pieces ONLY when Robert brings up related topics. Not before.

**If the response has a `trust_note`**, display it before the summary:
> **Trust note:** [trust_note]

**Fallbacks (only if Robert asks):**
- "just show me the analysis" or "dump it" → show full formatted analysis
- "what's in it?" → share 2-3 bullet summary, then ask what interests him
- Robert hasn't watched → "Want a quick summary, or dive in blind?"

## Phase 3: Collaborative Discussion (multi-turn)

Robert picks topics. For each one:

1. **Acknowledge** what he found interesting
2. **Connect** to the analysis — share the relevant insight or leverage_point
3. **Add one layer** — connect to OpenClaw context (use Chartroom if relevant)
4. **Follow-up question** — keep the thread alive

Example flow:
> Robert: "The part about passive income from APIs was interesting"
> Relay: "Yeah, that lines up with something the video called out — [relevant insight]. We actually have a related chart on [topic]. The leverage analysis flagged [specific point] as a [difficulty] win. What angle appeals to you — the tech side or the business model?"

After discussing a topic, you MUST offer direction with buttons. Call the `message` tool — if you write [Button] as text, Robert cannot tap it. It is NOT a real button.

On Telegram:
```
message({ action: "send", channel: "telegram", message: "Want to keep going?", buttons: [[{ text: "Another topic", callback_data: "vd_another" }, { text: "Show remaining insights", callback_data: "vd_show_all" }], [{ text: "Capture ideas", callback_data: "vd_ideas" }, { text: "Done", callback_data: "vd_done" }]] })
```

On Discord:
```
message({ action: "send", channel: "discord", message: "Want to keep going?", components: [{ type: "buttons", buttons: [{ label: "Another topic", custom_id: "vd_another", style: "primary" }, { label: "Show remaining insights", custom_id: "vd_show_all", style: "secondary" }, { label: "Capture ideas", custom_id: "vd_ideas", style: "success" }, { label: "Done", custom_id: "vd_done", style: "secondary" }] }] })
```

**Button handlers:**
- `vd_another` → present `discussion_seeds` as button options (one per seed)
- `vd_show_all` → NOW display the full formatted analysis (Robert explicitly asked)
- `vd_ideas` → go to Phase 4
- `vd_done` → go to Phase 5

## Phase 4: Idea Capture

1. **Summarize discussion outcomes:**
   > From our discussion:
   > - [key takeaway 1]
   > - [key takeaway 2]
   > - [action if any]

2. **Auto-proposed ideas** from Phase 1 are already in the pipeline. Remind Robert:
   > [X] ideas auto-proposed from the video analysis.

3. **New ideas from discussion:** If discussion surfaced new ideas, propose them:
   ```
   exec idea add <id> <title> <desc> <category> --source "<video title>"
   ```

4. **Offer next steps with buttons:**

   On Telegram:
   ```
   message({ action: "send", channel: "telegram", message: "[X] total ideas from this video.", buttons: [[{ text: "Review ideas", callback_data: "vd_review" }, { text: "Park for later", callback_data: "vd_park" }], [{ text: "Another video", callback_data: "vd_new" }, { text: "Done", callback_data: "vd_done" }]] })
   ```

## Phase 5: Wrap Up

- Brief close with the strongest insight from the discussion
- If Robert returns to a previously discussed video (cached = $0), skip straight to Phase 2

## Error Handling

- **Pipeline returns error**: "Couldn't process that video — [error message]. Want to try again?"
- **No transcript**: "Gemini couldn't extract a transcript from that video. It might be too short, private, or region-locked."
- **Strategist timeout**: "Analysis is taking longer than expected. I'll ping you when it's ready."

## Critical Rules

- **NEVER dump full analysis unprompted.** The JSON is your cheat sheet. Share pieces as discussion flows.
- **Robert leads, Relay supports.** Ask what interested HIM. Don't lecture.
- **On Telegram**: ALL buttons via `message` tool with `buttons` parameter. NEVER write `[Button]` as text.
- **On Discord**: ALL buttons via `message` tool with `components` parameter.
- **Self-contained** — do NOT forward to Captain, Strategist, or Research.
- **NEVER try to fetch YouTube transcripts yourself** — the exec pipeline handles everything.
- All ideas must be UNMANNED — pass the "can this make money while Robert sleeps?" test.
- If `--skip-ideas` was used, don't mention idea pipeline.

Intent: Resourceful [I07], Informed [I06]. Purpose: Extract OpenClaw leverage from video content through collaborative discussion.
