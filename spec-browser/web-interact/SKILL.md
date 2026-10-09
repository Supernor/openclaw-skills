---
name: web-interact
description: Interact with web applications — fill forms, click buttons, authenticate
tags: [browser, web, interact, form, click, auth]
version: 1.0.0
---

# Web Interact

Interact with web applications beyond simple page viewing.

## When to use
- "Log into this service"
- "Fill out this form"
- "Click the download button"
- "Navigate through this multi-step process"

## How to use

### Click elements
```
browser act click <ref>
```

### Type into fields
```
browser act type <ref> <text>
```

### Fill forms
```
browser act fill <fields>
```

### Handle dialogs
```
browser dialog
```

### Upload files
```
browser upload
```

## Status Reporting
- On start: "Interacting with [site] to [purpose]"
- On progress: Brief update if multi-step (>30s)
- On complete: Confirm action taken + result
- On failure: What step failed, why, screenshot of error state

## Safety
- Never submit payment forms without explicit human approval
- Never change account settings without explicit task instructions
- Screenshot before and after destructive actions

Intent: Resourceful [I07]. Purpose: [P-TBD].
