---
name: research-estimate
description: Estimate cost of a research task before executing it. Gate expensive tasks with human approval.
tags: [research, cost, estimate, gemini, approval, budget]
version: 1.0.0
---

# Research Estimate

Estimate the cost of a research request BEFORE executing it. If over threshold, present the human with choices instead of running it.

## When to use
- Before ANY research task that involves Gemini API calls
- The `research` skill should call this first as a gate
- Directly when asked "how much would it cost to research X?"

## Cost Estimation Method

### Step 1: Determine search path
- **Web search** → `web-search` skill (ops.db task). Free tier primary, paid Flash Lite failover. Cost: $0 or ~$0.001 per search.
- **Deep analysis** → Gemini API direct call. Cost varies by model.

### Step 2: Estimate output tokens
Based on research type:
- Simple web search: ~$0 (free tier) or ~$0.001 (paid failover)
- News summary (daily digest): ~$0.001
- Deep research with citations: ~$0.005
- Multi-source analysis: ~$0.01
- Comprehensive report: ~$0.05+

### Step 3: Calculate cost
Current pricing (update as pricing changes):

**Web search via Gemini CLI** (preferred)
- Free tier: $0 (250/day limit, 10 RPM)
- Paid failover (Flash Lite, thinking:low): ~$0.001 per search

**Gemini Flash (API, for heavier tasks)**
- Input: $0.10 per 1M tokens
- Output: $0.40 per 1M tokens

For scheduled/recurring tasks, multiply by frequency:
```
dailyCost = singleCost * 1
monthlyCost = singleCost * 30
```

### Step 4: Gate decision

**Under $0.05 per run**: Execute immediately. Report cost in result.

**$0.05 - $0.50 per run**: Execute, but flag the cost prominently in the result.

**Over $0.50 per run**: DO NOT EXECUTE. Instead, send a cost approval request to the human via Captain/Relay with these choices:

Default approval view (user can customize):

```
Research: [topic summary]

            Pro          Flash
Per run:    $X.XX        $X.XX
Monthly:    $X.XX        $X.XX    (if scheduled daily)

[Run with Pro] — Full depth at $X.XX
[Run with Flash] — Faster, $X.XX
[Narrow scope] — Tell me what to cut
[Skip] — Don't run this
```

Always estimate BOTH models so the human can compare. The cost difference is the information — let them decide the tradeoff.

The threshold is $0.50 by default. Captain can override per-task. The view layout itself is a user preference — this is the default. Relay renders whatever format the human prefers.

## After Execution: Report Actual Cost

Every research result must include:
```
Token usage: [input] in / [output] out / [thinking] think
Actual cost: $X.XXXX
Model used: [flash/pro]
```

Track cumulative spend in workspace MEMORY.md under "Gemini Token Spend Log".

## Scheduled Task Cost Projection

For recurring research (like daily AI news):
1. Run the first instance
2. Record actual cost
3. Project: daily, weekly, monthly
4. If monthly projection > $5: flag to human with the projection and ask if frequency or scope should change

## Example

```
Research request: "Daily AI news digest covering 4 providers"
Estimated: ~1,200 tokens in, ~2,000 tokens out, ~800 thinking
Per-run cost: $0.0005 (Flash)
Daily: $0.0005, Monthly: $0.015
Verdict: Under threshold. Execute immediately.
```

```
Research request: "Comprehensive competitive analysis of 10 AI coding tools"
Estimated: ~3,000 tokens in, ~10,000 tokens out, ~5,000 thinking (Pro needed)
Per-run cost: $0.06 (Pro)
Verdict: Over $0.05. Execute but flag cost.
```

Intent: Efficient [I06]. Purpose: [P-TBD].
