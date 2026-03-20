#!/bin/bash
# create-forum-topic.sh — Create a new forum topic in the Ideas group
# Usage: create-forum-topic.sh <name>
# Example: create-forum-topic.sh "🟢 My New Idea"
# Returns: topic_id (message_thread_id) on success

CHAT_ID="-1003545051047"
NAME="$1"

if [ -z "$NAME" ]; then
  echo "Usage: create-forum-topic.sh <name>"
  exit 1
fi

RESULT=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN_SCRIBE}/createForumTopic" \
  -d "chat_id=${CHAT_ID}" \
  --data-urlencode "name=${NAME}")

OK=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ok','false'))" 2>/dev/null)

if [ "$OK" = "True" ] || [ "$OK" = "true" ]; then
  TOPIC_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['message_thread_id'])" 2>/dev/null)
  echo "$TOPIC_ID"
else
  echo "FAIL: $RESULT" >&2
  exit 1
fi
