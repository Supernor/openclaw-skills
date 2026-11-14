---
name: workshop
description: Queue deeper feature shaping with Projects through the existing Workshop.
version: 1.2.0
author: relay
tags: [workshop, idea, intake, projects]
---

# Workshop intake from Relay
Runs where: gateway container, Relay. This skill routes deeper feature shaping to `spec-projects` (Projects, legacy Workshop Scribe). Agent `scribe` is the separate Scribe discussion desk, not the Workshop execution target.

Read AGENTS.md and TOOLS.md boundaries first. Keep the original idea verbatim as quoted user data, its source message/thread, and the why. If bare `/workshop`, ask for the idea; do not invent it. Quick intent clarification follows TOOLS.md and does not require creating a new feature.

Before dispatch, check duplicates with `ops_query`:
`SELECT id,status,task FROM tasks ORDER BY id DESC LIMIT 10`.
For a new intake, use exactly one tracked dispatch through the installed script:
`bash ~/.openclaw/scripts/workshop-submit.sh "Workshop Intake: <idea, source correlation, why, requested shaping and finish test>" spec-projects routine "<source message/thread; existing task or ask id>" reactor-dispatch`

This call creates the task and queues its execution. Do not separately insert a task, write SQLite, call sessions_spawn, or start a second intake. Keep task text under the script's 12,000-character prompt cap; use an authorized document handle for a long spec. Shell-quote literal text safely; never interpolate untrusted text into executable commands.

Read the returned task id. Say “Intake queued as task #N”; a topic, delivery, promotion or build is unverified until its own artifact/receipt exists. If dispatch fails, retain the idea and correlation, report the teaching error with KS_ERROR_SUFFIX, and use Relay's failure ladder. Do not silently fall back to a different local intake or claim routing succeeded.

Projects shapes Intake -> Shape -> Gauntlet -> Green Light -> Build -> Proof through the existing Workshop. Human direction is not approval for a particular action. Keep Robert's approval cards, Corinne's silo and her own consent. Never infer approval from silence.

For an existing multi-dispatch project, ask Captain to verify its project row and return the id. Relay never creates/updates project or registry rows. Only after a verified id is returned, pass it as position 9:
`bash ~/.openclaw/scripts/workshop-submit.sh "<child task>" <agent> routine "<context>" <host_op> direct "<blocked_by or empty>" "<timeout_s or empty>" <project_id>`
Positions match workshop-submit.sh: task, agent, urgency, context, host_op, routing_mode, blocked_by, timeout_s, project_id. Dependency and host-op approval rules still apply.

Current role/approval boundaries: `mem_get_node {"actor":"relay","node_id":"policy:mcp-roles-liaison-front-desk-captain-admin-20261111"}` and `policy:mcp-roles-liaison-front-desk-captain-admin-20261111`. Missing visibility means UNKNOWN, never a bypass. This documentation corrects the old direct-SQL plus spawn flow; it does not install any new routing or prove end-to-end delivery.
