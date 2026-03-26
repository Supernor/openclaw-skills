---
name: web-search
description: Queue a web search via Gemini CLI on the host. Free tier, no API cost. Results return via ops.db.
version: 1.0.0
author: research
tags: [search, web, gemini, free]
intent: Informed [I18]
---

# web-search

Queue a web search through Gemini CLI on the host (free tier, google_web_search built in).

## When to use
- Any research request requiring current web information
- Replaces direct `web_search` tool calls (which burn paid Google API tokens)
- Use for: news lookups, competitor research, documentation searches, fact-checking

## Process
1. Create an ops.db task via the gateway `tasks_create` tool:
   ```json
   {
     "agent": "spec-research",
     "task": "web-search: <brief description>",
     "meta": {
       "host_op": "gemini-search",
       "query": "<the actual search query — be specific>",
       "telegram_chat_id": "<chat_id if results should go to Telegram>"
     },
     "urgency": "routine"
   }
   ```
2. The host-ops-executor polls every 30s and runs `gemini-task` with the query
3. Results are stored in the task's `result` field in ops.db
4. If `telegram_chat_id` is set, results also push to Telegram

## Cost
Free — uses Gemini CLI free tier (10 RPM, 250 requests/day).

## Limitations
- Async: ~30-90s latency (poll interval + search time)
- Free tier rate limits: 10 RPM, 250/day. If exhausted, task blocks with 429 error.
- Results are text summaries, not raw HTML
