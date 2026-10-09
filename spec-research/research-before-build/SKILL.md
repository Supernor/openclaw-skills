---
name: research-before-build
description: Research methods, libraries, and patterns BEFORE coding. Prevents building the wrong thing.
tags: [research, pre-build, methods, architecture]
version: 1.0.0
---

# research-before-build

Research approach and methods BEFORE any code is written. Mandatory for Workshop Build stage.

## When to use
- Idea reaches Build stage in Workshop
- New feature requires technology decision
- Agent asks "how should I build X?"
- Any task that touches unfamiliar code/APIs/libraries

## Process

### Step 1: What exists already? (zero tokens)
- Chart search: `chart search "<topic>"` — we may have built this before
- Repo search: check if OpenClaw upstream already has the feature
- ops.db: check if a previous task attempted this and what happened

### Step 2: OpenClaw upstream check (zero tokens)
```bash
# What's in upstream we haven't pulled?
git fetch origin 2>/dev/null
git log --oneline origin/main..HEAD -- <relevant-path> | head -10
# Search upstream for the feature
git log --all --oneline --grep="<keyword>" | head -10
```

### Step 3: Web research (free via Gemini)
Use `web-search` skill with targeted queries:
- "[library/API] best practices 2026"
- "[task type] Python implementation patterns"
- "[specific error or API] documentation"
- "OpenClaw [feature] how to"

Research questions to answer:
1. Does a library/tool already solve this? (Don't reinvent)
2. What are the common pitfalls?
3. What's the simplest implementation that works?
4. What will break if we do this wrong?

### Step 4: Method recommendation (may cost tokens for synthesis)
Only call a model if Steps 1-3 produced conflicting or complex results that need synthesis.

## Output Format
```
## Pre-Build Research: [Topic]
**Question**: [What we need to build]
**Existing solutions found**: [Libraries, upstream features, prior attempts]
**Recommended approach**: [Simplest path that works]
**Pitfalls to avoid**: [Common mistakes, from web research]
**Dependencies**: [What we need to install/configure]
**Estimated complexity**: [Trivial/Small/Medium/Large]
**Cost of research**: [Zero / Free web search / N tokens]
```

## This research feeds into Workshop Shape
The findings populate Shape fields:
- `capability_needed` ← recommended approach
- `risk` ← pitfalls to avoid  
- `dependencies` ← what's needed
- `success_criteria` ← how to verify it works
