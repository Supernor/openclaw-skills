---
name: docs-read
description: Read content from a Google Doc
tags: [docs, document, read, content, google-docs]
---
# Docs Read
## When to use
When reading the content of a Google Doc for processing or summarization.
## Execution
1. Parse: doc ID (from URL or direct ID)
2. Run: `gog docs cat <doc-id> --account relay.supernor@gmail.com`
   - For metadata: `gog docs info <doc-id> --account relay.supernor@gmail.com`
3. Return document content
## Account Routing
- Route through correct Google account based on initiating agent/human
## Logging
- Log via log-event
