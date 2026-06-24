#!/usr/bin/env bash
# github-cli.sh — Golden script for GitHub CLI operations.
# Runs gh commands on the host where gh is installed and authed.
# Agents trigger via host_op="github-cli" with the command in meta.prompt.
#
# Usage: github-cli.sh "gh repo list Supernor --limit 10"
#        github-cli.sh "gh secret list --repo Supernor/openclaw-config"
#
# Security: only allows gh commands, not arbitrary shell.

set -eo pipefail

COMMAND="${1:?Usage: github-cli.sh 'gh command args...'}"

# Security: must start with 'gh '
if [[ ! "$COMMAND" == gh\ * ]]; then
    echo "ERROR: Command must start with 'gh '. Got: $COMMAND"
    exit 1
fi

# Resolve the GitHub token LIVE (dynamic single source of truth = gh's stored
# login), not a static .env copy that goes stale when auth rotates (the
# 2026-06-24 lockout broke a month of backups exactly this way). `gh-token`
# strips any stale inherited GH_TOKEN and falls back to .env only if gh is down.
export GH_TOKEN=$(/usr/local/bin/gh-token)

if [ -z "$GH_TOKEN" ]; then
    echo "ERROR: GH_TOKEN not set. Add to /root/openclaw/.env"
    exit 1
fi

# Execute the gh command
eval "$COMMAND"
