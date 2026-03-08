---
name: script
description: Write bash or node scripts for automation tasks. Usage: /script <description>
version: 1.0.0
author: dev
tags: [script, automation, bash, node]
---

# script

## Invoke

```
/script <what the script should do>
```

## Steps

### 1. Understand requirements
- What triggers this script? Manual, cron, hook, agent?
- What inputs does it need?
- What outputs should it produce?
- Where should it live?

### 2. Check existing scripts
```bash
ls ~/.openclaw/scripts/
```
Look for similar functionality. Extend rather than duplicate.

### 3. Write the script

**Bash scripts:**
- Use `set -euo pipefail` at the top
- Add usage/help for any script with arguments
- Use meaningful variable names
- Quote all variables
- Handle errors with clear messages
- Exit with appropriate codes

**Node scripts:**
- Use ESM imports
- Handle errors with try/catch
- Use process.exit codes
- Accept arguments via process.argv or a simple arg parser

### 4. Make executable and test
```bash
chmod +x <script-path>
bash <script-path> --help  # or dry-run
```

### 5. Report

```
RESULT: Script created at <path>
STATUS: success
USAGE: <how to run it>
VERIFY: <test command>
```

## Rules
- Scripts go in `~/.openclaw/scripts/` unless they are skill-specific
- Always include a --help or usage message
- Always test before reporting done
- Runtime installs vanish on rebuild — flag if the script needs packages
- Prefer bash for simple automation, node for complex logic

Intent: Competent [I03]. Purpose: [P-TBD].
