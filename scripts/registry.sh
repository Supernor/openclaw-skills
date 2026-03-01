#!/usr/bin/env bash
# registry.sh — Query the shared registry
# Usage:
#   registry.sh get discord.channels.ops-alerts    → 1477754571697688627
#   registry.sh get discord.colors.green           → 5763719
#   registry.sh get paths.modelHealth              → /home/node/.openclaw/model-health.json
#   registry.sh get scripts.keyDrift               → key-drift-check.sh (name only)
#   registry.sh script keyDrift                    → /home/node/.openclaw/scripts/key-drift-check.sh (full path)
#   registry.sh channel ops-alerts                 → 1477754571697688627 (shortcut)
#   registry.sh color green                        → 5763719 (shortcut)
#   registry.sh dump                               → full registry JSON

set -eo pipefail

REGISTRY="/home/node/.openclaw/registry.json"

if [ ! -f "$REGISTRY" ]; then
  echo "ERROR: registry.json not found at $REGISTRY" >&2
  exit 1
fi

CMD="${1:?Usage: registry.sh <get|script|channel|color|dump> [key]}"

case "$CMD" in
  get)
    KEY="${2:?Usage: registry.sh get <dotted.key>}"
    jq -r ".${KEY}" "$REGISTRY"
    ;;
  script)
    NAME="${2:?Usage: registry.sh script <scriptKey>}"
    SCRIPTS_DIR=$(jq -r '.paths.scripts' "$REGISTRY")
    SCRIPT_NAME=$(jq -r ".scripts.${NAME}" "$REGISTRY")
    if [ "$SCRIPT_NAME" = "null" ]; then
      echo "ERROR: unknown script key: $NAME" >&2
      exit 1
    fi
    echo "${SCRIPTS_DIR}/${SCRIPT_NAME}"
    ;;
  channel)
    NAME="${2:?Usage: registry.sh channel <channelName>}"
    jq -r ".discord.channels.\"${NAME}\"" "$REGISTRY"
    ;;
  color)
    NAME="${2:?Usage: registry.sh color <colorName>}"
    jq -r ".discord.colors.${NAME}" "$REGISTRY"
    ;;
  dump)
    cat "$REGISTRY"
    ;;
  *)
    echo "Usage: registry.sh <get|script|channel|color|dump> [key]" >&2
    exit 1
    ;;
esac
