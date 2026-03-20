#!/bin/bash
# edit-forum-topic.sh — Change a forum topic's name via direct Telegram Bot API
# Usage: edit-forum-topic.sh <chat_id> <topic_id> <new_name>
# Example: edit-forum-topic.sh -1003545051047 210 "🟡 Job Search for Robert"
#
# Available to Scribe via exec tool (pathPrepend includes scripts dir)

CHAT_ID="$1"
TOPIC_ID="$2"
NEW_NAME="$3"

if [ -z "$CHAT_ID" ] || [ -z "$TOPIC_ID" ] || [ -z "$NEW_NAME" ]; then
  echo "Usage: edit-forum-topic.sh <chat_id> <topic_id> <new_name>"
  exit 1
fi

RESULT=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN_SCRIBE}/editForumTopic" \
  -d "chat_id=${CHAT_ID}" \
  -d "message_thread_id=${TOPIC_ID}" \
  --data-urlencode "name=${NEW_NAME}")

OK=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('ok','false'))" 2>/dev/null)

if [ "$OK" = "True" ] || [ "$OK" = "true" ]; then
  echo "OK: Topic ${TOPIC_ID} renamed to '${NEW_NAME}'"
else
  echo "FAIL: $RESULT"
  exit 1
fi
