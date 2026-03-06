---
name: security-scan
description: Run security audits using OpenClaw's native security and secrets tools
tags: [security, audit, secrets]
version: 1.0.0
---

# Security Scan

Run security audits using OpenClaw's built-in tools.

## When to use
- Periodic security check-in
- After config changes or new agent additions
- Before any external-facing changes

## Commands

### Config audit
```bash
oc security audit --json                # Basic audit
oc security audit --deep --json         # Including live gateway probes
oc security audit --fix                 # Auto-fix safe issues
```

### Secrets audit
```bash
oc secrets audit --json                 # Check for plaintext secrets, unresolved refs
oc secrets audit --check                # Exit non-zero if findings (for automation)
```

### Full scan (run both)
```bash
oc security audit --deep --json && oc secrets audit --json
```

## Integration
- Route results to Security Officer: `oc agent --agent spec-security --message "Analyze this audit: $(oc security audit --json)" --json`
- Chart findings: `chart add "security-scan-<date>" "<findings>" "reading" 0.9`

## Rules
- Run after every new agent is added
- Run after config changes that touch auth or channels
- Never auto-fix without reviewing findings first (use --json, then decide)
