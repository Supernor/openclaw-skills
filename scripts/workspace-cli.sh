#!/usr/bin/env bash
# Alignment: golden script for Google Workspace CLI operations.
# Role: execute gws commands on behalf of a specific agent's Google account.
# Dependencies: gws CLI (npm @googleworkspace/cli), per-agent credential dirs
# at /root/.openclaw/gws-credentials/<account>/, ops.db for task tracking.
# Key patterns: account isolation — each agent uses its own Google account and
# credential store via GWS config dir override. Commands are passed as the prompt
# field in task meta. Supports all gws services: drive, sheets, gmail, calendar,
# docs, slides, tasks, people, chat, forms, keep, meet, script, admin.
# Reference: /root/.openclaw/docs/policy-context-injection.md

set -eo pipefail

ACCOUNT="${1:?Usage: workspace-cli.sh ACCOUNT 'gws command...'}"
COMMAND="${2:?Usage: workspace-cli.sh ACCOUNT 'gws command...'}"

# Account-to-credential mapping
# Each agent's Google account gets its own isolated gws config directory
CRED_DIR="/root/.openclaw/gws-credentials/$ACCOUNT"

if [ ! -d "$CRED_DIR" ]; then
    echo "ERROR: No credentials for account '$ACCOUNT'."
    echo "Available accounts:"
    ls /root/.openclaw/gws-credentials/ 2>/dev/null || echo "  (none — run gws auth setup first)"
    echo ""
    echo "Setup: GOOGLE_WORKSPACE_CLI_CONFIG_DIR=$CRED_DIR gws auth login"
    exit 1
fi

# Export config dir so gws uses the right account's credentials
export GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$CRED_DIR"
export GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND="file"

# Execute the gws command
# The command is the full gws invocation minus the 'gws' prefix
# e.g., "drive files list --params '{\"pageSize\": 10}'"
eval gws $COMMAND 2>&1
