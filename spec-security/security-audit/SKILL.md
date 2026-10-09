---
name: security-audit
description: Systematic security audit of a specific area of the OpenClaw deployment
tags: [security, audit, config, permissions, vulnerability]
version: 1.0.0
---

# Security Audit

Perform a focused security audit on a specific area.

## When to use
- "Check if any API keys are exposed"
- "Audit the Docker configuration"
- "Review agent permissions"
- "Security check on [area]"

## Audit Areas

### 1. Secrets Exposure
- Scan workspace files for API keys, tokens, passwords
- Check .env files for proper scoping
- Verify openclaw.json doesn't contain raw secrets
- Check git history for accidentally committed secrets

### 2. Container Security
- Review Docker compose configuration
- Check for unnecessary privileged mode or capabilities
- Verify volume mount scope (are we mounting too much?)
- Check container user permissions

### 3. Agent Permissions
- Review each agent's tool access
- Check for overly broad allowedTools
- Verify agent-to-agent communication restrictions
- Look for prompt injection vectors in agent inputs

### 4. Infrastructure
- Check SSH configuration (key-only? root login?)
- Review open ports (only what's needed?)
- Check for pending security updates
- Review firewall rules

### 5. Discord Security
- Review bot permissions in Discord
- Check for token exposure in logs
- Verify webhook URLs aren't in public files

## Process
1. Identify the audit area
2. Run relevant checks
3. Classify each finding by severity
4. Verify findings (no false alarms)
5. Report to Captain with recommended actions

## Output
Use the reporting format from SOUL.md. Every finding must include severity, verification status, and a recommended action for when the Security Officer reaches the appropriate trust level.

Intent: Secure [I16]. Purpose: [P-TBD].
