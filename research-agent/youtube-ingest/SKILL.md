---
name: youtube-ingest
description: Ingest YouTube video transcripts into the transcript database using Gemini API
tags: [youtube, transcript, ingest, gemini, research, external]
version: 1.0.0
---

# /youtube-ingest — YouTube Transcript Ingestion

Extracts transcripts from YouTube videos via the Gemini API (native YouTube processing) and stores them in the transcript SQLite database.

## When to use
- User or Captain requests transcript extraction from YouTube videos
- Research needs to ingest external video content for analysis
- Building knowledge base from video sources

## Command Grammar

```
/youtube-ingest <url>                    — Ingest single video
/youtube-ingest <url1> <url2> ...        — Ingest multiple videos
/youtube-ingest --channel <handle> --days <N>  — Ingest recent videos from channel
```

## Execution

Run the handler script:
```bash
bash ~/.openclaw/scripts/youtube-ingest.sh "$@"
```

## How it works
1. Takes YouTube URL(s) or channel handle
2. Calls Gemini API (`gemini-3-flash-preview`) with native YouTube video processing
3. Extracts: transcript (complete), description, upload date
4. Stores in `/root/.openclaw/transcripts.db` with metadata
5. All entries marked: source=external, trust_level=0.9, trusted_by=Robert

## Database Schema
```sql
videos(video_id, title, publish_date, url, description, transcript,
       summary, key_insights, source, trust_level, trusted_by, channel, created_at)
```

## Notes
- Gemini API processes YouTube URLs natively — no cookies, no proxy needed
- ~30s per video, 20-40K chars of transcript each
- Rate limit: 2s between API calls to avoid 429s
- YouTube blocks direct access from this VPS (cloud IP) — ONLY the Gemini API method works
- Cost: Gemini Flash pricing per video (~0.5M tokens input per video)

## Known Issues
- Gemini sometimes returns wrong upload dates — use channel posting cadence for verification
- Very long videos (>2hr) may timeout at 180s — retry with longer timeout
- See chart: issue-youtube-cloud-ip-block

Intent: Informed [I18]. Purpose: External knowledge ingestion.
