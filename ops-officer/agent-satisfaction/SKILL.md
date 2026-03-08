---
name: agent-satisfaction
description: Score all agents across the 17 satisfaction intents. Generates a comprehensive report with per-agent scores (1-10) and system-level scores.
version: 1.0.0
author: ops-officer
tags:
  - agent
  - satisfaction
  - health
  - wellbeing
  - team
  - scores
trigger:
  command: /agent-satisfaction
  keywords:
    - agent satisfaction
    - team health
    - agent scores
    - wellbeing check
---

# agent-satisfaction

Score all agents across the 17 satisfaction intents.

## Procedure

1. Run the scoring script:
   ```bash
   bash /home/node/.openclaw/scripts/agent-satisfaction-score.sh
   ```

2. Review the output — scores each agent on 11 per-agent intents and 6 system intents

3. Identify any scores below 6 — these need attention

4. For low scores, propose specific actions:
   - Focus < 6: Propose agent split
   - Voice < 5: Trace pipeline, find drop point
   - Harmony < 5: Identify friction source
   - Equipped < 6: Seed missing charts, create skills
   - Clarity < 5: Rewrite SOUL.md
   - Trusted < 5: Investigate completion rate, handoff reliability

5. Store the report in Chartroom:
   ```
   memory_store report-agent-satisfaction "<summary>" --importance 1.0 --category fact
   ```

6. Post summary to `#ops-dashboard` if any agent scores critically low (avg < 5)

## Output
Full ASCII report with bar charts, per-intent scores, and action recommendations.

Intent: Observable [I13]. Purpose: [P-TBD].
