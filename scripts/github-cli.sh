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

# Load GH_TOKEN from .env if not already set
if [ -z "$GH_TOKEN" ]; then
    if [ -f /root/openclaw/.env ]; then
        export GH_TOKEN=$(grep "^GH_TOKEN=" /root/openclaw/.env | cut -d= -f2-)
    fi
fi

if [ -z "$GH_TOKEN" ]; then
    echo "ERROR: GH_TOKEN not set. Add to /root/openclaw/.env"
    exit 1
fi

# Execute the gh command
eval "$COMMAND"
