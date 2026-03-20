#!/bin/bash
# pin-message.sh — Pin a message in a Telegram chat/topic
# Usage: pin-message.sh <chat_id> <message_id>
# Example: pin-message.sh -1003545051047 347

CHAT_ID="$1"
MESSAGE_ID="$2"

if [ -z "$CHAT_ID" ] || [ -z "$MESSAGE_ID" ]; then
  echo "Usage: pin-message.sh <chat_id> <message_id>"
  exit 1
fi

RESULT=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN_SCRIBE}/pinChatMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "message_id=${MESSAGE_ID}" \
  -d "disable_notification=true")

OK=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ok','false'))" 2>/dev/null)

if [ "$OK" = "True" ] || [ "$OK" = "true" ]; then
  echo "OK: Message ${MESSAGE_ID} pinned"
else
  echo "FAIL: $RESULT"
  exit 1
fi
