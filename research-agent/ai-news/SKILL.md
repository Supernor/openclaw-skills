---
name: ai-news
description: Produce daily AI news digest for the team
tags: [news, ai, daily, digest, intelligence]
version: 1.0.0
---

# AI News

Produce a daily AI news digest covering developments that affect Robert, Corinne, and Claude Code.

## When to use
- Daily scheduled run (via heartbeat or cron)
- "What's new in AI today?"
- "Any updates from [provider]?"
- "Catch me up on AI news"

## Categories (start simple, refine over time)

### 1. Provider Updates
News from model providers we actively use — these are PRIORITY watches:
- **Anthropic** (Claude Opus 4.6, Sonnet 4.6, Haiku 4.5) — Opus powers our Reactor via Claude Code Max. Sonnet reserved for future use. Track: new model releases, pricing changes, context window changes, tool use improvements, Max plan policy changes, session limit changes.
- **OpenAI** (GPT-5.3 Codex) — primary model for all 8 agents via ChatGPT Plus OAuth. Track: model updates, OAuth stability, capability changes, pricing, new features we could leverage.
- **Google** (Gemini 3 Flash, Gemini 3.1 Pro) — Research Agent's primary tool + fallback for all agents. Track: pricing changes, new grounding features, multimodal improvements, API changes, deprecations (we got burned by gemini-3-pro deprecation).
- **OpenRouter** — our catch-all default + future multi-model routing potential. Track: new models added, pricing transparency, routing improvements, cost optimization features.
- **Meta** (Llama) — open source, future potential via OpenRouter
- Others as relevant

When a provider update affects our config, cost, or capabilities: chart it immediately and flag for Captain. **NEVER propose auto-applying model changes** — model changes in openclaw.json have crashed the gateway historically. Research RECOMMENDS, Captain EVALUATES, Robert APPROVES, Reactor EXECUTES. See Chartroom: `procedure-model-change-safe`.

### 2. Impact Assessment
For each piece of news:
- Does this affect our model config?
- Does this change our costs?
- Does this unlock new capabilities?
- Does this break anything we depend on?

### 3. Actionable Decisions
- Things we should change now
- Things to investigate further
- Things to watch but not act on yet

### 4. Opportunity Signals (grow over time)
- Cost optimization opportunities
- New tools or integrations worth evaluating
- Competitive intelligence

## Source Quality
- Check MEMORY.md for source trust scores before citing
- If citing a new source, add it to the tracking list
- Never include unverified rumors without flagging uncertainty
- Prefer primary sources (official blogs, papers) over secondary coverage

## Output Format
Store as Chartroom reading: `reading-ai-news-YYYY-MM-DD`

```
## AI News — [Date]

### Provider Updates
- [Provider]: [What happened]. Impact: [none/low/medium/high]. Action: [none/investigate/change].

### Decisions Needed
- [Decision]: [Context]. Recommended: [action].

### Watching
- [Topic]: [Why we care]. Next check: [when].

Sources: [list with trust ratings]
```

## Learning Loop
After each digest:
- Did any previous "watch" items become actionable?
- Did any source prove wrong on a previous claim? Update trust score.
- Are new categories emerging? Note them in MEMORY.md.

Intent: Informed [I18]. Purpose: [P-TBD].
