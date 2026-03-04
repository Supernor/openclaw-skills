---
name: tasks
description: Task tracking per project channel. Add, update, complete, assign, and list tasks. Usage: /task <subcommand>
version: 1.0.0
author: scribe
tags: [tasks, project, tracking]
---

# tasks

## Invoke

```
/task add <title>                              # Add a new task
/task add <title> --assign <agent>             # Add and assign
/task add <title> --link <dec#>                # Add linked to a decision
/task add <title> --verify "how to check"      # Add with verification criteria
/task add <title> --done-when "acceptance"      # Add with done criteria
/task done <id>                                # Mark task complete
/task update <id> <status>                     # Change status (todo, in-progress, done, blocked)
/task assign <id> <agent>                      # Assign to an agent
/task verify <id> <criteria>                   # Set how to verify the task worked
/task done-when <id> <criteria>                # Set acceptance criteria
/task list                                     # Show all tasks
/task list --status todo                       # Filter by status
/task remove <id>                              # Delete a task
/tasks                                         # Alias for /task list
```

## Script

All operations go through the script:
```bash
/home/node/.openclaw/scripts/task-manager.sh <action> <channel> [args]
```

The `<channel>` is the Discord channel name where the command was invoked.

## Steps

### 1. Determine channel
Use the channel name from the task context. This becomes the task file key.

### 2. Run the script
Map the user's subcommand to the script action:

| User command | Script call |
|-------------|-------------|
| `/task add Fix the bug` | `task-manager.sh add <channel> Fix the bug` |
| `/task add Fix bug --assign spec-github` | `task-manager.sh add <channel> Fix the bug --assign spec-github` |
| `/task done 3` | `task-manager.sh done <channel> 3` |
| `/task update 2 in-progress` | `task-manager.sh update <channel> 2 in-progress` |
| `/task assign 1 spec-github` | `task-manager.sh update <channel> 1 <current-status> --assign spec-github` |
| `/task list` | `task-manager.sh list <channel>` |
| `/task list --status todo` | `task-manager.sh list <channel> todo` |
| `/task remove 5` | `task-manager.sh remove <channel> 5` |
| `/task verify 2 Run test suite` | `task-manager.sh set-verify <channel> 2 Run test suite` |
| `/task done-when 2 All tests pass` | `task-manager.sh set-done-when <channel> 2 All tests pass` |
| `/tasks` | `task-manager.sh list <channel>` |

### 3. Format output

**After add:**
```
RESULT: Created task #<id>: <title>
STATUS: success
```

**After done:**
```
RESULT: Completed task #<id>: <title>
STATUS: success
```

**After list:** Format as a compact board. Show verify/doneWhen if set:
```
RESULT: Task board for #<channel>

📋 Todo (2)
  #1 Build login page → spec-github
     ✓ Verify: Page renders at /login
     ✓ Done when: Login form submits and redirects
  #4 Add error handling

🔄 In Progress (1)
  #2 Design auth flow (linked: decision #1)

🚫 Blocked (0)

✅ Done (3)
  #3 Write tests
  #5 Deploy staging
  #6 Fix typo

STATUS: success
```

## Valid Statuses
`todo`, `in-progress`, `done`, `blocked`

## Storage
Tasks stored in `tasks/<channel-name>.json` — managed exclusively by the script.

## Rules
- Always use the script — never edit task JSON directly
- Channel name = task namespace — tasks don't cross channels
- Task IDs are auto-incremented, never reused
- If no channel context, ask which project
