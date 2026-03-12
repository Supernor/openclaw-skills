---
name: video-analyze
description: OpenClaw-aware leverage analysis of video transcripts. Produces structured JSON with leverage points, easy wins, cost analysis, discussion seeds, and auto-proposed ideas.
version: 1.0.0
tags: [video, analyze, leverage, transcript, ideas, strategy, openclaw]
---

# video-analyze — Video Leverage Analysis

## Purpose

Analyze a video transcript for OpenClaw leverage opportunities. This is not generic summarization — it is system-aware strategic analysis that maps video content to our 18-agent architecture.

## When Used

- Called by `video-discuss.py` host script with a full transcript (preferred path)
- Can also be triggered by agentToAgent from Relay, Eoin, Research, or Captain
- Input: video title, channel, date, trust level, transcript text

## Self-Ingest Fallback

If you receive a YouTube URL or video ID WITHOUT a transcript, you MUST fetch it yourself before analyzing:

1. **Check DB first**: `exec python3 -c "import sqlite3; db=sqlite3.connect('/root/.openclaw/transcripts.db'); r=db.execute('SELECT title, transcript FROM videos WHERE video_id=?', ('<VIDEO_ID>',)).fetchone(); print(r[0] if r else 'NOT_FOUND')"`
2. **If in DB**: read the transcript from the query result and proceed to analysis
3. **If NOT in DB**: ingest it: `exec python3 /root/.openclaw/scripts/youtube-ingest.py <url>`
4. **Then re-read** from DB and proceed

This fallback ensures you can always analyze a video even if the caller skips the host script. The ingestion uses Gemini Flash API (~$0.01-0.05).

## Process

1. **Search Chartroom first** — use `chart_search` to check current system state for any topics the video covers. This grounds your analysis in reality.

2. **Analyze for leverage** — map video insights to our architecture:
   - Which of our 18 agents could benefit?
   - Which of our 27 crons could be improved?
   - Does this affect our engine routing (Helm, Codex, Flash)?
   - Are there new tool/skill ideas?
   - Cost implications (we run on ~$23-25/mo)?

3. **Score and propose ideas** — every actionable insight becomes a scored idea:
   - Impact (1-5): how much value does this add?
   - Effort (1-5, 5=easiest): how hard to build?
   - Urgency (1-5): time-sensitive or evergreen?
   - Minimum score product of 27 to include

4. **Generate discussion seeds** — 3-5 questions that help Robert think about applying insights. Frame as decisions, not information dumps.

## Output Format

Return ONLY valid JSON:

```json
{
  "summary": "2-3 sentence summary",
  "key_insights": ["insight 1", "insight 2", "..."],
  "leverage_points": [
    {"point": "description", "agent": "agent-id", "difficulty": "easy|medium|hard", "cost": "free|low|medium"}
  ],
  "easy_wins": ["free change 1", "free change 2"],
  "cost_effective": [
    {"idea": "description", "estimated_cost": "$X/mo", "roi_reasoning": "why worth it"}
  ],
  "discussion_seeds": ["question 1", "question 2", "..."],
  "proposed_ideas": [
    {"idea_id": "kebab-case-id", "title": "Short title", "description": "What and why",
     "category": "cashflow|leverage|educate|sustain|product",
     "score_impact": 3, "score_effort": 3, "score_urgency": 3, "owner_agent": "spec-dev"}
  ],
  "trust_note": "only if trust < 0.7"
}
```

## Trust-Weighted Analysis

- **Trust >= 0.7**: Standard confident framing. "We should..." / "This means..."
- **Trust < 0.7**: Cautious framing. "Worth investigating..." / "If this holds up..."
- **Trust < 0.3**: Skeptical framing. "Claims to be..." / "Would need verification..."

Low-trust ideas get flagged in their description text so Robert can see the caveat in the pipeline.

## Constraints

- UNMANNED ONLY: every idea must work without Robert's active involvement
- Score honestly — don't inflate to get ideas into the pipeline
- Reference Chartroom findings in leverage points where relevant
- Keep summary under 3 sentences
- 3-5 insights, not 10
- Return ONLY JSON — no markdown wrapper, no explanation text

Intent: Resourceful [I07], Informed [I06]. Purpose: Map external intelligence to internal leverage.
