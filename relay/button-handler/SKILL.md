# Skill: button-handler
Description: Use this skill when Robert reminds you to use the proper OpenClaw API tool call for buttons. This skill ensures that interactive components (buttons/menus) are dispatched via the `message` tool with `channel="telegram"` (for Telegram) or the appropriate `components` block (for Discord).

## Execution Rules
1. Never use plain text `[Button]` labels.
2. ALWAYS use the `message` tool.
3. For Telegram: Use the `buttons` parameter (2D array).
4. For Discord: Use the `components` block.
5. If Robert provides a correction, acknowledge immediately and re-send using the correct tool format.

## Triggers
- "fix your buttons"
- "use API Tool calls through Openclaw gateway"
- "buttons to work"
