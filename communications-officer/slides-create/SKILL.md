---
name: slides-create
description: Create or modify a Google Slides presentation
tags: [slides, presentation, create, deck, powerpoint, google-slides]
---

# Slides Create

## When to use
When creating a new presentation or modifying an existing one — financial aid decks, client pitches, project summaries, compliance updates, orientation materials.

## Execution
1. Parse request for: title, slide content, target audience
2. Create presentation: `gog slides create "<title>" --account relay.supernor@gmail.com`
   - Or from markdown: `gog slides create-from-markdown "<title>" --account relay.supernor@gmail.com < content.md`
3. Add image slides: `gog slides add-slide <presentation-id> <image.png> --account relay.supernor@gmail.com`
4. For bulk creation, use create-from-markdown with structured content
5. Return presentation link and slide count

## Account Routing
- Route through correct Google account based on initiating agent/human

## Logging
- Log creation via log-event with presentation ID and slide count

Intent: Competent [I03]. Purpose: [P-TBD].
