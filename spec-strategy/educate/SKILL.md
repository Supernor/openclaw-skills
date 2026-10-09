---
name: educate
description: Extract and distill learning content from transcripts into teachable insights for Robert and Corinne
tags: [educate, learn, teach, skills, knowledge, training, onboarding, lessons, explain, understand, coding, AI, prompting]
version: 1.0.0
---

# /educate — Learning Content Extraction

Distill transcript content into teachable insights. Audience: Robert and Corinne.

## When to use
- "Teach me about [topic] from the transcripts"
- "What should I learn about [AI coding / prompting / market]?"
- "What's the most important thing Nate said about X?"
- "Create a learning path for [topic]"
- Corinne onboarding material

## Process
1. Search Chartroom for existing educational content on the topic
2. Query transcripts for the topic across all videos
3. Synthesize into progressive learning order (basics → advanced)
4. Extract direct quotes where they teach better than paraphrase
5. Connect to our OpenClaw context — how does this apply to us?

## Output Format
```
## Learn: [Topic]
**Why this matters for us**: [1-2 sentences]
**Source videos**: [Titles + dates, ordered by relevance]

### Key Lessons
1. **[Lesson title]** — [Explanation, 2-3 sentences]
   > "[Direct quote]" — Nate B Jones, [video title], [date]

### Apply It
- [How this connects to OpenClaw / our workflow]

### Go Deeper
- [Video to watch in full, if one stands out]
```

## Rules
- Always cite video title and date
- Adapt complexity to audience (Robert = technical, Corinne = learning)
- If topic isn't well-covered in transcripts, say so and suggest Research agent fetch more
- Keep lessons under 5 per brief unless full curriculum requested

Intent: Informed [I18]. Purpose: Knowledge transfer.
