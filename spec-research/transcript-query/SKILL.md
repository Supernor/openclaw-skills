---
name: transcript-query
description: Search and query the YouTube transcript database for actionable intelligence
tags: [youtube, transcript, search, query, research, knowledge]
version: 1.0.0
---

# /transcript-query — Search Video Transcripts

Searches the transcript database by keyword, date range, topic, or channel. Returns relevant excerpts with context.

## When to use
- User asks "what did [creator] say about [topic]?"
- Need to find specific advice, predictions, or insights from video content
- Building briefings from external video intelligence
- Checking if a topic was already covered in ingested content

## Command Grammar

```
/transcript-query <keywords>                        — Full-text search
/transcript-query <keywords> --after YYYY-MM-DD     — Date-filtered search
/transcript-query --recent N                        — Last N videos
/transcript-query --stats                           — Database overview
/transcript-query --insights <keywords>             — Search key_insights column
```

## Execution

Run the handler script:
```bash
python3 ~/.openclaw/scripts/transcript-query.py "$@"
```

## Output Format
Returns matching transcript excerpts with:
- Video title and date
- Relevant passage (±500 chars around match)
- Summary if available
- Key insights if available

Intent: Informed [I18]. Purpose: External knowledge retrieval.
