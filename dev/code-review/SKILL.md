---
name: code-review
description: Review code for correctness, style, security, and maintainability. Usage: /code-review <file-or-description>
version: 1.0.0
author: dev
tags: [code, review, quality]
---

# code-review

## Invoke

```
/code-review <file-path>           # Review a specific file
/code-review <description>         # Review based on description
```

## Steps

### 1. Read the code
Read the target file or files completely. Understand the context.

### 2. Check for issues in priority order
1. **Correctness**: Does it do what it claims? Logic errors, off-by-ones, null handling
2. **Security**: Injection, auth bypass, secret exposure, OWASP top 10
3. **Error handling**: Silent failures, bare catches, missing validation at boundaries
4. **Performance**: Obvious N+1 queries, unbounded loops, missing indexes
5. **Style**: Consistency with surrounding code, naming, readability

### 3. Report findings

```
RESULT: Code review for <target>

🔴 Critical (must fix):
- <issue + line + fix suggestion>

🟡 Important (should fix):
- <issue + line + fix suggestion>

🔵 Nit (optional):
- <issue + line + fix suggestion>

✅ Good patterns noticed:
- <what works well>

STATUS: <clean | issues-found | critical-issues>
```

## Rules
- Prioritize issues by severity — do not bury critical bugs under style nits
- Suggest fixes, not just problems
- Respect existing conventions — do not propose rewrites for style preference
- Be specific: file, line number, what is wrong, what to do instead
