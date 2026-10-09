---
name: mistake-log
description: Log a mistake or failure with context, cause, and lesson. Maintain the unified mistake registry. Track patterns across engines and agents.
version: 1.0.0
author: historian
tags: [mistake, error, pattern, learning]
intent: Informed [I18]
---

Log a mistake or analyze mistake patterns.

When logging a new mistake:
1. Record: WHAT happened, WHO (engine/agent), WHEN, WHY (root cause), IMPACT
2. Search existing `engine-mistakes-*` and `pattern-mistake-*` charts for similar issues
3. If pattern exists, update it with new occurrence count
4. If new pattern, chart as `pattern-mistake-<name>` category `error`
5. Link to relevant session journal

When analyzing patterns:
1. Search all mistake charts
2. Group by: engine, agent, category, frequency
3. Identify top recurring issues
4. Produce actionable recommendations
