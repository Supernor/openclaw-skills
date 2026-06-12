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
# Works on host (/root/.openclaw) and in container (/home/node/.openclaw)
if [ -d "/root/.openclaw/gws-credentials/$ACCOUNT" ]; then
  CRED_DIR="/root/.openclaw/gws-credentials/$ACCOUNT"
elif [ -d "/home/node/.openclaw/gws-credentials/$ACCOUNT" ]; then
  CRED_DIR="/home/node/.openclaw/gws-credentials/$ACCOUNT"
else
  CRED_DIR="/root/.openclaw/gws-credentials/$ACCOUNT"
fi

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
if command -v gws >/dev/null 2>&1; then
  GWS_BIN="gws"
elif [ -x "/root/.openclaw/vendor/gws/node_modules/.bin/gws" ]; then
  GWS_BIN="/root/.openclaw/vendor/gws/node_modules/.bin/gws"
elif [ -x "/home/node/.openclaw/vendor/gws/node_modules/.bin/gws" ]; then
  GWS_BIN="/home/node/.openclaw/vendor/gws/node_modules/.bin/gws"
else
  echo "ERROR: Google Workspace CLI binary not found for workspace-cli.sh."
  echo "WHAT: workspace-cli.sh needs the gws executable to run '$COMMAND' for account '$ACCOUNT'."
  echo "HISTORY: Tried command -v gws, /root/.openclaw/vendor/gws/node_modules/.bin/gws, and /home/node/.openclaw/vendor/gws/node_modules/.bin/gws; none were executable."
  echo "NOT TRIED: No runtime npm install was attempted inside the container; container changes must come from the host bind mount."
  echo "WORKED BEFORE: Host vendoring with npm install --prefix /root/.openclaw/vendor/gws @googleworkspace/cli provides /home/node/.openclaw/vendor/gws/node_modules/.bin/gws in the gateway container."
  echo "FIX: On the host, run: mkdir -p /root/.openclaw/vendor/gws && npm install --prefix /root/.openclaw/vendor/gws @googleworkspace/cli"
  exit 1
fi

eval $GWS_BIN $COMMAND 2>&1
