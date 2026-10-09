---
name: research
description: Deep research on a topic using web search and analysis capabilities
tags: [research, search, analysis, web]
version: 2.0.0
---

# Research

Conduct deep research on a topic. Research agent owns all web search for the fleet.

## When to use
- "Research this topic"
- "What are the current best practices for X?"
- "Find out about this company/tool/service"
- "Fact-check this claim"
- Any agent needing web search routes through Research via Captain

## Process
1. Search Chartroom first — we may already know this
2. Formulate a clear research question
3. **RUN research-estimate FIRST** — mandatory cost gate
4. If estimate is over $0.50: STOP, send approval choices to human via Captain/Relay
5. For web search: use the `web-search` skill (queues Gemini CLI on host, free tier primary, paid Flash Lite failover)
6. Verify key claims across multiple sources
7. Structure findings: what we learned, confidence level, sources, impact on us
8. Report results back to the requesting agent and/or user via Captain/Relay

## Status Reporting
- On start: "Researching [topic] via [Gemini search/multimodal/etc]"
- On complete: Structured findings + sources + confidence + token cost
- On failure: What broke + token cost of failed attempt

## Cost Discipline
- **research-estimate is MANDATORY before expensive operations**
- Web search via `web-search` skill: free (Gemini CLI free tier) or pennies (paid Flash Lite failover)
- Under $0.05: execute, report cost
- $0.05-$0.50: execute, flag cost prominently
- Over $0.50: DO NOT execute — send choices to human via Relay buttons
- Track spend in workspace MEMORY.md

## Output Format
```
## Research: [Topic]
**Question**: [What was asked]
**Findings**: [Key points, numbered]
**Sources**: [URLs with trust ratings]
**Confidence**: [High/Medium/Low + why]
**Impact on us**: [What this means for OpenClaw]
**Suggested action**: [If any]
**Token cost**: [Estimated spend for this research]
```

Intent: Informed [I18]. Purpose: [P-TBD].
