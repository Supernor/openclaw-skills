#!/usr/bin/env bash
# discord-scan.sh — Dynamic Discord server structure scanner
# Usage:
#   discord-scan.sh                    # Full server scan (categories + channels)
#   discord-scan.sh category <name>    # Find category by name
#   discord-scan.sh channel <name>     # Find channel by name
#   discord-scan.sh channels <cat-id>  # List channels in a category
#
# Returns JSON. Agents call this instead of maintaining static channel lists.

set -eo pipefail

# Token from env — works both on host and in container
TOKEN="${OPENCLAW_PROD_DISCORD_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f /root/openclaw/.env ]; then
  TOKEN=$(grep OPENCLAW_PROD_DISCORD_TOKEN /root/openclaw/.env 2>/dev/null | cut -d= -f2)
fi
if [ -z "$TOKEN" ]; then
  echo '{"error":"Discord token not found"}' | jq .
  exit 1
fi

GUILD_ID="1477115265300037703"
API="https://discord.com/api/v10"

ACTION="${1:-scan}"

case "$ACTION" in
  scan)
    # Full server structure: categories with their channels
    curl -s -H "Authorization: Bot $TOKEN" "$API/guilds/$GUILD_ID/channels" | jq '
      # Separate categories and channels
      (map(select(.type == 4)) | sort_by(.position)) as $cats |
      (map(select(.type != 4)) | sort_by(.position)) as $chans |
      {
        guild: "'"$GUILD_ID"'",
        categories: [$cats[] | {
          id: .id,
          name: .name,
          position: .position,
          channels: [$chans[] | select(.parent_id == $cats[0].id // empty) | {id: .id, name: .name, topic: .topic}]
        }] | map(. + {
          channels: [($chans | .[] | select(.parent_id == .id)) // empty]
        }),
        uncategorized: [$chans[] | select(.parent_id == null) | {id: .id, name: .name, topic: .topic}]
      }
    ' 2>/dev/null || \
    # Fallback: simpler parse if jq fails on complex query
    curl -s -H "Authorization: Bot $TOKEN" "$API/guilds/$GUILD_ID/channels" | jq '[.[] | {id, name, type, parent_id, topic, position}] | sort_by(.position)'
    ;;

  category)
    NAME="${2:?Usage: discord-scan.sh category <name>}"
    curl -s -H "Authorization: Bot $TOKEN" "$API/guilds/$GUILD_ID/channels" | jq --arg name "$NAME" '
      [.[] | select(.type == 4 and (.name | ascii_downcase | contains($name | ascii_downcase)))] |
      if length == 0 then {error: "No category matching: \($name)"}
      else .[0] | {id, name, position}
      end
    '
    ;;

  channel)
    NAME="${2:?Usage: discord-scan.sh channel <name>}"
    curl -s -H "Authorization: Bot $TOKEN" "$API/guilds/$GUILD_ID/channels" | jq --arg name "$NAME" '
      [.[] | select(.type != 4 and (.name | ascii_downcase | contains($name | ascii_downcase)))] |
      if length == 0 then {error: "No channel matching: \($name)"}
      else map({id, name, topic, parent_id})
      end
    '
    ;;

  channels)
    CAT_ID="${2:?Usage: discord-scan.sh channels <category-id>}"
    curl -s -H "Authorization: Bot $TOKEN" "$API/guilds/$GUILD_ID/channels" | jq --arg cat "$CAT_ID" '
      [.[] | select(.parent_id == $cat)] | sort_by(.position) | map({id, name, topic})
    '
    ;;

  *)
    echo '{"error":"Usage: discord-scan.sh [scan|category|channel|channels] [args]"}' | jq .
    exit 1
    ;;
esac
