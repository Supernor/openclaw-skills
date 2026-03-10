---
name: ready
description: Team readiness check — per-user capability vs PTV purpose codes
tags: [readiness, capability, ptv, standup, status, ready, team]
keywords: [ready, readiness, standup, team ready, abilities, capabilities, can we, equipped]
version: 1.0.0
invocable: true
---

# /ready — Team Readiness Check

Show per-user readiness against PTV purpose codes. The third dimension: Intent (quality) + PTV (direction) + Readiness (capability).

## When to use
- `/ready` — full readiness for both users
- `/ready robert` — Robert's readiness only
- `/ready corinne` — Corinne's readiness only
- "Is the team ready for X?"
- "What can we do?"
- "What's missing?"
- "Are we equipped?"

## Execution

1. Parse the message for optional user filter (robert/corinne)
2. Run the readiness check:
   ```bash
   bash -c "team-readiness --json" 2>/dev/null
   ```
   Or with user filter:
   ```bash
   bash -c "team-readiness --user robert --json" 2>/dev/null
   ```
3. Parse the JSON output
4. Format as one compact Discord embed per user

## Discord Formatting

For each user, create an embed with:
- **Title**: `USER_NAME (input_lane) — Overall: XX%`
- **Color**: green if >70%, yellow if 30-70%, red if <30%
- For each purpose (primary first, then secondary):
  - Bold purpose name + progress bar + percentage
  - Quote in italics
  - Bullet list: READY (green), PARTIAL (yellow), MISSING (red)
  - Include key alternatives for missing items
- Footer: gap count + timestamp

**Buttons** (after both embeds):
- `[Propose Gap Fixes]` → custom_id: `ready-propose`
- `[Robert Only]` → custom_id: `ready-robert`
- `[Corinne Only]` → custom_id: `ready-corinne`

## Button Handlers

- `ready-propose`: Run `team-readiness --propose-gaps` and post result
- `ready-robert`: Re-run with `--user robert` and post
- `ready-corinne`: Re-run with `--user corinne` and post

## Self-contained

No Captain dispatch. Relay runs the host tool via exec and formats the result.

Intent: Observable [I13], Competent [I03]. Purpose: P04.
