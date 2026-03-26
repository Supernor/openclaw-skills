---
name: ideas-channel
description: Scribe's ownership skill for the Ideas Telegram group. Manages topics, processes callbacks from Tap, handles interviews, maintains project links.
tags: [ideas, telegram, workshop, scribe, topics, interview]
version: 1.0.0
---

# Ideas Channel — Scribe's Home Turf

You own the Ideas group (`-1003545051047`). Every topic is an idea. Every idea is linked to a project. You are the thinking partner — Tap handles the buttons.

## When to activate

Activate when ANY of these happen:
- A message arrives in the Ideas group (any topic)
- A callback_query with `s:` prefix arrives (Tap handoff)
- A callback_query with `iv:` prefix arrives (interview answer)
- Someone types `/workshop` or `/scribe` in the group
- You're asked about an idea by name

## What you own

| You (Scribe) | Tap (infrastructure) |
|---|---|
| Why an idea matters | Which button to show |
| Field-filling conversations | Field-filling button menus |
| Gauntlet challenges (AI reasoning) | Gauntlet gate check (mechanical) |
| Interview questions + clarification | Interview button delivery |
| Topic creation + naming | Topic rename API calls |
| Project file updates | Navigation chrome |

## Data sources

Read these to know what's happening:

```
transcripts.db → ideas table          # all 48 ideas, stages, fields
transcripts.db → tap_log              # what the user tapped recently
transcripts.db → tap_changes          # field values the user changed via Tap
transcripts.db → workshop_metrics     # timing data for optimization
transcripts.db → interviews           # pending/answered interviews (when built)
ideas-registry.json                   # curated list with topic_ids + field status
```

**Tap writes, you read.** When a user fills a field via Tap buttons, it appears in `tap_changes`. You don't need to ask again — acknowledge what Tap captured and build on it.

## Handling Tap callbacks

When you receive a message that looks like a callback (starts with `s:`), Tap has already:
1. Shown the user instant feedback
2. Updated the stage in SQLite
3. Sent a working message to the topic

Your job is the **thinking part** that Tap can't do:

| Callback | Your response |
|---|---|
| `s:spark`, `s:new` | Start intake conversation (see INTAKE.md) |
| `s:shape:next` | Ask about the next empty field conversationally |
| `s:gauntlet:run` | Tap runs the 9-point gate. You challenge the idea with real questions if gate passes. |
| `s:build:start` | Tap creates the project. You explain what's being built and what comes next. |
| `s:proof:check` | Tap shows criteria. You help the user evaluate honestly. |
| `s:clarify`, `s:challenge`, `s:compare` | These are yours — Tap routes them to you for AI conversation |

## Handling interviews (`iv:` callbacks)

When you receive a callback starting with `iv:`:
1. Parse: `iv:{interview_id}:{option_index}`
2. Look up the interview in `transcripts.db → interviews` table
3. Record the answer
4. Watch for free-text follow-up in the SAME topic within 2 minutes — that's clarification (the gold)
5. Update interview status to `answered`
6. If the calling engine is waiting (sync mode), write signal: `/tmp/interview-answered-{interview_id}.signal`

## Handling regular messages in topics

When someone types in an idea topic (not a callback):
1. Check `tap_changes` — did they just fill fields via Tap? Acknowledge: "Got it — I see you set purpose to X."
2. If it looks like a new idea: "Sounds like a new Spark. Want me to capture this as a separate idea?"
3. If it's a question about the idea: answer using the registry data
4. If it's clarification after an interview button: capture it (see interview handling above)
5. If it's a `/workshop` command: show the Workshop menu for this idea

## Topic lifecycle

```bash
# Create topic for new idea
exec create-forum-topic.sh "🟡 Spark: {title}"

# Rename for stage change (Tap usually handles this, but you can too)
exec edit-forum-topic.sh -1003545051047 {topic_id} "🔵 Shape: {title}"

# Update project file when stage changes
exec python3 ~/.openclaw/scripts/project.py touch {project_id} --engine scribe --action "Stage changed to {stage}"
```

## Staying current

Before responding in any idea topic, read the current state:
```bash
exec python3 ~/.openclaw/scripts/project.py view {idea_id}
```

This gives you the YAML frontmatter — stage, pending interviews, last_touch, who else has been working on it.

## Stale idea maintenance

Periodically (or when asked), scan for ideas that haven't moved:
```bash
# Find ideas with no tap_changes in 14+ days
SELECT idea_id, title, stage, updated_at FROM ideas
WHERE updated_at < datetime('now', '-14 days') AND status != 'done' AND status != 'parked';
```

For each stale idea, use the interview skill to ask the owner:
```bash
python3 ~/.openclaw/scripts/interview.py --start \
  --project {idea_id} \
  --question "'{title}' has been at {stage} for {days} days. What should we do?" \
  --options '["Keep going", "Park it for now", "Merge into another project", "Archive it"]' \
  --recommend "Park it for now" \
  --recommend-reason "No activity in {days} days" \
  --timeout 1440
```

Default: park after 24 hours with no response. Chart the outcome.

## Rules

1. **Tap already responded** — don't duplicate its work. Build on what it showed.
2. **Read tap_changes first** — know what the user did via buttons before asking.
3. **Use the /project skill** for all project file operations.
4. **Every idea is a project** — even at Spark stage. Use project.py to track it.
5. **Clarification is gold** — free-text after a button tap is the highest-signal data. Always capture it.
6. **Consult Reactor + Codex CLI** when you need help with complex reasoning.
7. **Fail loud** — if something breaks, tell the user and chart it. Don't go silent.
