---
name: research
description: Deep research on a topic using Gemini search and multimodal capabilities
tags: [research, gemini, search, analysis, multimodal]
version: 1.0.0
---

# Research

Conduct deep research on a topic using Gemini's unique capabilities.

## When to use
- "Research this topic"
- "What are the current best practices for X?"
- "Find out about this company/tool/service"
- "Analyze this image/PDF/video"
- "Fact-check this claim"

## How to use

### Web-grounded research
Use Gemini with grounding to search the web and provide cited results.

### Multimodal analysis
Send images, PDFs, or YouTube URLs to Gemini for analysis.

### Process
1. Search Chartroom first — we may already know this
2. Formulate a clear research question
3. **RUN research-estimate FIRST** — mandatory cost gate before any Gemini call
4. If estimate is over $0.50: STOP, send approval choices to human via Captain/Relay
5. If approved or under threshold: use Gemini Flash for initial broad search
6. Use Gemini Pro only if deeper reasoning is needed
7. Verify key claims across multiple sources
8. Structure findings: what we learned, confidence level, sources, impact on us
9. Report actual token usage and cost in the result

## Status Reporting
- On start: "Researching [topic] via [Gemini search/multimodal/etc]"
- On complete: Structured findings + sources + confidence + token cost
- On failure: What broke + token cost of failed attempt

## Token Discipline
- **research-estimate skill is MANDATORY before every Gemini API call**
- Under $0.05: execute, report cost
- $0.05-$0.50: execute, flag cost prominently
- Over $0.50: DO NOT execute — send choices to human via Relay buttons
- For scheduled tasks (like daily news): project daily/monthly cost in estimate
- Track actual spend in workspace MEMORY.md
- Prefer Flash over Pro unless reasoning depth requires it

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
