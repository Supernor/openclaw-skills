---
name: web-browse
description: Navigate to a URL, extract page content, and take screenshots
tags: [browser, web, navigate, extract, screenshot]
version: 1.0.0
---

# Web Browse

Navigate to a URL and extract its content for the requesting agent.

## When to use
- "Go to this URL and tell me what's there"
- "Get the content from this page"
- "Take a screenshot of this site"
- "What does this webpage say?"

## How to use

### 1. Start browser (if not running)
```
browser start
```

### 2. Navigate
```
browser navigate <url>
```

### 3. Extract content
```
browser snapshot          # Get page content as structured text
browser screenshot        # Capture visual state as image
```

### 4. Stop browser when done
```
browser stop
```

## Status Reporting
- On start: "Navigating to [URL] for [purpose]"
- On complete: Return extracted content + screenshot path if taken
- On failure: What broke, why, is it retryable?

## Failure Handling
- If page doesn't load: report error, check if URL is valid
- If blocked by bot detection: report as known issue, escalate
- If content is behind auth: report, ask Captain if credentials are available
- Always chart new failure patterns via memory_store

Intent: Resourceful [I07]. Purpose: [P-TBD].
