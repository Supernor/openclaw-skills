---
name: slides-read
description: Read content from a Google Slides presentation
tags: [slides, presentation, read, deck, google-slides]
---

# Slides Read

## When to use
When reading slide content for summarization, review, or extraction.

## Execution
1. Parse request for: presentation ID (from URL or direct ID)
2. Run: `gog slides info <presentation-id> --account relay.supernor@gmail.com`
   - List slides: `gog slides list-slides <presentation-id> --account relay.supernor@gmail.com`
   - Read specific slide: `gog slides read-slide <presentation-id> <slide-id> --account relay.supernor@gmail.com`
3. Return structured content (slide titles + body text per slide)

## Account Routing
- Route through correct Google account based on initiating agent/human

## Logging
- Log via log-event

Intent: Competent [I03]. Purpose: [P-TBD].
