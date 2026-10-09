---
name: topic
description: Show or set the topic/scope for the current project channel. Usage: /topic [description]
version: 1.0.0
author: relay
tags: [project, scope, topic]
---

# topic

## Invoke

```
/topic                              # Show current topic
/topic Voice wake word integration  # Set the topic
```

## Steps

### 1. If no argument — show topic

Read `projects/<channel-name>.md` and display the Topic field.

If no project file exists: "No project scope set for this channel. Use `/topic <description>` to set one."

### 2. If argument — set topic

Update the Topic field in `projects/<channel-name>.md`.

If the project file doesn't exist, create it (same format as `/project` creates).

Also set the Discord channel topic (the description shown at the top of the channel):
```
PATCH /channels/<channel_id>
{
  "topic": "<description>"
}
```

### 3. Confirm

```
📌 Topic for **#<channel-name>** set: <description>
```

## Behavior — Topic Scoping

When the topic is set for a channel, the agent should:

- **Stay on topic** — responses should be relevant to the channel's scope
- **Redirect drift** — if the user asks about something unrelated, acknowledge it and suggest moving to the appropriate channel or creating a new project
- **Example redirect:** "That's more of an infrastructure question — want me to move this to #ops, or should we `/project` a new channel for it?"

## Rules

- Topic is stored in `projects/<channel-name>.md` AND the Discord channel description
- Keep topics to one sentence (under 100 chars)
- If bot lacks permission to set Discord channel topic, just update the local file and note the limitation

Intent: Responsive [I04]. Purpose: [P-TBD].
