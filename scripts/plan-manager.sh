#!/usr/bin/env bash
# plan-manager.sh — Project plan lifecycle management
# Usage:
#   plan-manager.sh create <title> --agent <id> --channel <id> [--channel-name <name>]
#   plan-manager.sh add-phase <plan-id> <name> [--gate]
#   plan-manager.sh add-step <plan-id> <phase-id> <text>
#   plan-manager.sh add-decision <plan-id> <question> --options "a,b,c"
#   plan-manager.sh resolve-decision <plan-id> <decision-id> <answer>
#   plan-manager.sh approve <plan-id>
#   plan-manager.sh step-done <plan-id> <step-id>
#   plan-manager.sh advance <plan-id>
#   plan-manager.sh modify <plan-id> <change-text>
#   plan-manager.sh status <plan-id>
#   plan-manager.sh complete <plan-id>
#   plan-manager.sh reject <plan-id> [reason]
#   plan-manager.sh pause <plan-id>
#   plan-manager.sh resume <plan-id>
#   plan-manager.sh list [--active|--all]
#   plan-manager.sh card <plan-id>
#   plan-manager.sh archive <plan-id>

set -eo pipefail

BASE="/home/node/.openclaw"
PLANS_DIR="$BASE/plans"
TEMPLATES="$BASE/templates/plan-card.txt"
mkdir -p "$PLANS_DIR"

ACTION="${1:-}"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

err() { echo "{\"error\":\"$1\"}" | jq .; exit 1; }

[ -z "$ACTION" ] && err "Usage: plan-manager.sh <action> [args]"

# Generate short plan ID: 3 random chars + date
gen_id() {
  local slug
  slug=$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-20)
  local rand
  rand=$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-4)
  echo "${slug}-${rand}"
}

# Get plan file by ID (supports prefix match)
plan_file() {
  local id="$1"
  local f="$PLANS_DIR/${id}.json"
  if [ -f "$f" ]; then
    echo "$f"
    return
  fi
  # Try prefix match
  local matches
  matches=$(find "$PLANS_DIR" -maxdepth 1 -name "${id}*.json" 2>/dev/null | head -2)
  local count
  count=$(echo "$matches" | grep -c . 2>/dev/null || echo 0)
  if [ "$count" -eq 1 ] && [ -n "$matches" ]; then
    echo "$matches"
    return
  fi
  [ "$count" -gt 1 ] && err "Ambiguous plan ID '$id' — multiple matches"
  err "Plan not found: $id"
}

# Count steps by status across all phases
count_steps() {
  local file="$1" status="$2"
  jq --arg s "$status" '[.phases[].steps[] | select(.status == $s)] | length' "$file"
}

total_steps() {
  jq '[.phases[].steps[]] | length' "$1"
}

case "$ACTION" in
  create)
    shift
    TITLE=""
    AGENT=""
    CHANNEL_ID=""
    CHANNEL_NAME=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --agent) AGENT="$2"; shift 2 ;;
        --channel) CHANNEL_ID="$2"; shift 2 ;;
        --channel-name) CHANNEL_NAME="$2"; shift 2 ;;
        *) TITLE="$TITLE $1"; shift ;;
      esac
    done
    TITLE=$(echo "$TITLE" | sed 's/^ //')

    [ -z "$TITLE" ] && err "Title required"
    # Reject titles that look like flags (prevents garbage plans from --help etc.)
    [[ "$TITLE" == -* ]] && err "Title cannot start with '-'"
    [ -z "$AGENT" ] && AGENT="spec-projects"

    PLAN_ID=$(gen_id "$TITLE")
    PLAN_FILE="$PLANS_DIR/${PLAN_ID}.json"

    jq -n \
      --arg id "$PLAN_ID" \
      --arg title "$TITLE" \
      --arg agent "$AGENT" \
      --arg chId "$CHANNEL_ID" \
      --arg chName "$CHANNEL_NAME" \
      --arg now "$NOW" \
      '{
        id: $id,
        title: $title,
        status: "planning",
        agent: $agent,
        channelId: $chId,
        channelName: $chName,
        threadId: null,
        messageId: null,
        created: $now,
        updated: $now,
        approved: null,
        completed: null,
        phases: [],
        decisions: [],
        modifications: [],
        research: [],
        nextPhaseId: 1,
        nextStepId: 1,
        nextDecisionId: 1
      }' > "$PLAN_FILE"

    jq '{action: "created", id: .id, title: .title, status: .status}' "$PLAN_FILE"
    ;;

  add-phase)
    PLAN_ID="${2:-}"
    shift 2
    NAME=""
    GATE=false
    while [ $# -gt 0 ]; do
      case "$1" in
        --gate) GATE=true; shift ;;
        *) NAME="$NAME $1"; shift ;;
      esac
    done
    NAME=$(echo "$NAME" | sed 's/^ //')

    [ -z "$PLAN_ID" ] || [ -z "$NAME" ] && err "Usage: plan-manager.sh add-phase <plan-id> <name> [--gate]"

    FILE=$(plan_file "$PLAN_ID")
    STATUS=$(jq -r '.status' "$FILE")
    [ "$STATUS" != "planning" ] && [ "$STATUS" != "draft" ] && err "Plan must be in planning/draft status to add phases (current: $STATUS)"

    TMP=$(mktemp)
    PHASE_ID=$(jq '.nextPhaseId' "$FILE")
    jq --arg name "$NAME" --argjson gate "$GATE" --argjson pid "$PHASE_ID" --arg now "$NOW" '
      .nextPhaseId = ($pid + 1) |
      .updated = $now |
      .phases += [{
        id: $pid,
        name: $name,
        status: "pending",
        gate: $gate,
        steps: []
      }]
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    echo "{\"action\":\"phase_added\",\"phaseId\":$PHASE_ID,\"name\":\"$NAME\",\"gate\":$GATE}" | jq .
    ;;

  add-step)
    PLAN_ID="${2:-}"
    PHASE_ID="${3:-}"
    shift 3
    TEXT="$*"

    [ -z "$PLAN_ID" ] || [ -z "$PHASE_ID" ] || [ -z "$TEXT" ] && err "Usage: plan-manager.sh add-step <plan-id> <phase-id> <text>"

    FILE=$(plan_file "$PLAN_ID")
    STATUS=$(jq -r '.status' "$FILE")
    [ "$STATUS" != "planning" ] && [ "$STATUS" != "draft" ] && err "Plan must be in planning/draft status to add steps (current: $STATUS)"

    # Verify phase exists
    EXISTS=$(jq --argjson pid "$PHASE_ID" '[.phases[] | select(.id == $pid)] | length' "$FILE")
    [ "$EXISTS" -eq 0 ] && err "Phase $PHASE_ID not found"

    TMP=$(mktemp)
    STEP_ID=$(jq '.nextStepId' "$FILE")
    jq --argjson pid "$PHASE_ID" --argjson sid "$STEP_ID" --arg text "$TEXT" --arg now "$NOW" '
      .nextStepId = ($sid + 1) |
      .updated = $now |
      .phases = [.phases[] | if .id == $pid then .steps += [{id: $sid, text: $text, status: "todo"}] else . end]
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    echo "{\"action\":\"step_added\",\"stepId\":$STEP_ID,\"phaseId\":$PHASE_ID,\"text\":\"$TEXT\"}" | jq .
    ;;

  add-decision)
    PLAN_ID="${2:-}"
    shift 2
    QUESTION=""
    OPTIONS=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --options) OPTIONS="$2"; shift 2 ;;
        *) QUESTION="$QUESTION $1"; shift ;;
      esac
    done
    QUESTION=$(echo "$QUESTION" | sed 's/^ //')

    [ -z "$PLAN_ID" ] || [ -z "$QUESTION" ] || [ -z "$OPTIONS" ] && err "Usage: plan-manager.sh add-decision <plan-id> <question> --options \"a,b,c\""

    FILE=$(plan_file "$PLAN_ID")
    TMP=$(mktemp)
    DEC_ID=$(jq '.nextDecisionId' "$FILE")

    # Convert comma-separated options to JSON array
    OPTIONS_JSON=$(echo "$OPTIONS" | jq -R 'split(",")')

    jq --argjson did "$DEC_ID" --arg q "$QUESTION" --argjson opts "$OPTIONS_JSON" --arg now "$NOW" '
      .nextDecisionId = ($did + 1) |
      .updated = $now |
      .decisions += [{
        id: $did,
        question: $q,
        options: $opts,
        status: "pending",
        answer: null,
        pollId: null,
        created: $now
      }]
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    echo "{\"action\":\"decision_added\",\"decisionId\":$DEC_ID,\"question\":\"$QUESTION\"}" | jq .
    ;;

  resolve-decision)
    PLAN_ID="${2:-}"
    DEC_ID="${3:-}"
    shift 3
    ANSWER="$*"

    [ -z "$PLAN_ID" ] || [ -z "$DEC_ID" ] || [ -z "$ANSWER" ] && err "Usage: plan-manager.sh resolve-decision <plan-id> <decision-id> <answer>"

    FILE=$(plan_file "$PLAN_ID")
    TMP=$(mktemp)
    jq --argjson did "$DEC_ID" --arg ans "$ANSWER" --arg now "$NOW" '
      .updated = $now |
      .decisions = [.decisions[] | if .id == ($did | tonumber) then .status = "resolved" | .answer = $ans else . end]
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    echo "{\"action\":\"decision_resolved\",\"decisionId\":$DEC_ID,\"answer\":\"$ANSWER\"}" | jq .
    ;;

  approve)
    PLAN_ID="${2:-}"
    [ -z "$PLAN_ID" ] && err "Usage: plan-manager.sh approve <plan-id>"

    FILE=$(plan_file "$PLAN_ID")
    STATUS=$(jq -r '.status' "$FILE")
    [ "$STATUS" != "planning" ] && [ "$STATUS" != "draft" ] && [ "$STATUS" != "ready" ] && err "Plan must be in planning/draft/ready status to approve (current: $STATUS)"

    FIRST_PHASE=$(jq '.phases[0].id // empty' "$FILE")
    TMP=$(mktemp)
    jq --arg now "$NOW" --argjson fpid "${FIRST_PHASE:-0}" '
      .status = "executing" |
      .approved = $now |
      .updated = $now |
      .phases = [.phases[] | if .id == $fpid then .status = "active" else . end]
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    jq '{action: "approved", id: .id, status: .status, approved: .approved}' "$FILE"
    ;;

  step-done)
    PLAN_ID="${2:-}"
    STEP_ID="${3:-}"
    [ -z "$PLAN_ID" ] || [ -z "$STEP_ID" ] && err "Usage: plan-manager.sh step-done <plan-id> <step-id>"

    FILE=$(plan_file "$PLAN_ID")

    # Find and mark step done
    EXISTS=$(jq --argjson sid "$STEP_ID" '[.phases[].steps[] | select(.id == ($sid | tonumber))] | length' "$FILE")
    [ "$EXISTS" -eq 0 ] && err "Step $STEP_ID not found"

    TMP=$(mktemp)
    jq --argjson sid "$STEP_ID" --arg now "$NOW" '
      .updated = $now |
      .phases = [.phases[] | .steps = [.steps[] | if .id == ($sid | tonumber) then .status = "done" else . end]]
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    # Check if current phase is complete
    ACTIVE_PHASE=$(jq '[.phases[] | select(.status == "active")] | .[0].id // empty' "$FILE")
    if [ -n "$ACTIVE_PHASE" ]; then
      PHASE_REMAINING=$(jq --argjson pid "$ACTIVE_PHASE" '
        [.phases[] | select(.id == $pid) | .steps[] | select(.status != "done")] | length
      ' "$FILE")
      if [ "$PHASE_REMAINING" -eq 0 ]; then
        TMP2=$(mktemp)
        jq --argjson pid "$ACTIVE_PHASE" --arg now "$NOW" '
          .updated = $now |
          .phases = [.phases[] | if .id == $pid then .status = "done" else . end]
        ' "$FILE" > "$TMP2" && mv "$TMP2" "$FILE"
      fi
    fi

    DONE=$(count_steps "$FILE" "done")
    TOTAL=$(total_steps "$FILE")
    PCT=$(( DONE * 100 / (TOTAL > 0 ? TOTAL : 1) ))

    jq -n --argjson sid "$STEP_ID" --argjson done "$DONE" --argjson total "$TOTAL" --argjson pct "$PCT" \
      '{action: "step_done", stepId: $sid, progress: {done: $done, total: $total, percent: $pct}}'
    ;;

  advance)
    PLAN_ID="${2:-}"
    [ -z "$PLAN_ID" ] && err "Usage: plan-manager.sh advance <plan-id>"

    FILE=$(plan_file "$PLAN_ID")
    STATUS=$(jq -r '.status' "$FILE")
    [ "$STATUS" != "executing" ] && [ "$STATUS" != "gate" ] && err "Plan must be executing or at gate (current: $STATUS)"

    # Find next pending phase
    NEXT_PHASE=$(jq '[.phases[] | select(.status == "pending")] | .[0].id // empty' "$FILE")
    [ -z "$NEXT_PHASE" ] && err "No more phases to advance to"

    # Check if next phase has a gate and current phase just finished
    IS_GATE=$(jq --argjson pid "$NEXT_PHASE" '.phases[] | select(.id == $pid) | .gate' "$FILE")

    TMP=$(mktemp)
    if [ "$IS_GATE" = "true" ] && [ "$STATUS" != "gate" ]; then
      # Enter gate state — pause for Robert's approval
      jq --argjson pid "$NEXT_PHASE" --arg now "$NOW" '
        .status = "gate" |
        .updated = $now |
        .gatePhaseId = $pid
      ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

      jq '{action: "gate_reached", planId: .id, gatePhaseId: .gatePhaseId, status: "gate"}' "$FILE"
    else
      # Activate next phase
      jq --argjson pid "$NEXT_PHASE" --arg now "$NOW" '
        .status = "executing" |
        .updated = $now |
        .gatePhaseId = null |
        .phases = [.phases[] | if .id == $pid then .status = "active" else . end]
      ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

      jq --argjson pid "$NEXT_PHASE" '{action: "phase_activated", phaseId: $pid, status: "executing"}' "$FILE"
    fi
    ;;

  modify)
    PLAN_ID="${2:-}"
    shift 2
    CHANGE="$*"
    [ -z "$PLAN_ID" ] || [ -z "$CHANGE" ] && err "Usage: plan-manager.sh modify <plan-id> <change-text>"

    FILE=$(plan_file "$PLAN_ID")

    TMP=$(mktemp)
    jq --arg change "$CHANGE" --arg now "$NOW" '
      .status = "planning" |
      .updated = $now |
      .modifications += [{by: "robert", at: $now, change: $change}]
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    jq '{action: "modified", id: .id, status: .status, modification: .modifications[-1]}' "$FILE"
    ;;

  status)
    PLAN_ID="${2:-}"
    [ -z "$PLAN_ID" ] && err "Usage: plan-manager.sh status <plan-id>"

    FILE=$(plan_file "$PLAN_ID")

    DONE=$(count_steps "$FILE" "done")
    TOTAL=$(total_steps "$FILE")
    ACTIVE=$(jq -r '[.phases[].steps[] | select(.status == "active")] | length' "$FILE")
    PCT=$(( DONE * 100 / (TOTAL > 0 ? TOTAL : 1) ))
    PENDING_DECISIONS=$(jq '[.decisions[] | select(.status == "pending")] | length' "$FILE")

    jq --argjson done "$DONE" --argjson total "$TOTAL" --argjson pct "$PCT" \
       --argjson active "$ACTIVE" --argjson pendingDec "$PENDING_DECISIONS" '
      {
        id: .id,
        title: .title,
        status: .status,
        agent: .agent,
        created: .created,
        approved: .approved,
        progress: {done: $done, total: $total, active: $active, percent: $pct},
        pendingDecisions: $pendingDec,
        phases: [.phases[] | {id: .id, name: .name, status: .status, gate: .gate,
          steps: (.steps | length), done: ([.steps[] | select(.status == "done")] | length)}],
        modifications: (.modifications | length)
      }
    ' "$FILE"
    ;;

  complete)
    PLAN_ID="${2:-}"
    [ -z "$PLAN_ID" ] && err "Usage: plan-manager.sh complete <plan-id>"

    FILE=$(plan_file "$PLAN_ID")
    STATUS=$(jq -r '.status' "$FILE")
    [ "$STATUS" != "executing" ] && [ "$STATUS" != "gate" ] && err "Plan must be executing or at gate to complete (current: $STATUS)"

    TMP=$(mktemp)
    jq --arg now "$NOW" '
      .status = "complete" |
      .completed = $now |
      .updated = $now |
      .gatePhaseId = null |
      .phases = [.phases[] | if .status != "done" then .status = "done" else . end]
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    DONE=$(count_steps "$FILE" "done")
    TOTAL=$(total_steps "$FILE")

    jq --argjson done "$DONE" --argjson total "$TOTAL" '
      {action: "completed", id: .id, title: .title, done: $done, total: $total, duration: {created: .created, completed: .completed}}
    ' "$FILE"
    ;;

  reject)
    PLAN_ID="${2:-}"
    shift 2
    REASON="${*:-No reason given}"

    [ -z "$PLAN_ID" ] && err "Usage: plan-manager.sh reject <plan-id> [reason]"

    FILE=$(plan_file "$PLAN_ID")

    TMP=$(mktemp)
    jq --arg reason "$REASON" --arg now "$NOW" '
      .status = "rejected" |
      .updated = $now |
      .rejectReason = $reason
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    jq '{action: "rejected", id: .id, title: .title, reason: .rejectReason}' "$FILE"
    ;;

  pause)
    PLAN_ID="${2:-}"
    [ -z "$PLAN_ID" ] && err "Usage: plan-manager.sh pause <plan-id>"

    FILE=$(plan_file "$PLAN_ID")
    STATUS=$(jq -r '.status' "$FILE")
    [ "$STATUS" != "executing" ] && err "Plan must be executing to pause (current: $STATUS)"

    TMP=$(mktemp)
    jq --arg now "$NOW" '
      .status = "paused" |
      .updated = $now |
      .pausedAt = $now
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    jq '{action: "paused", id: .id, title: .title}' "$FILE"
    ;;

  resume)
    PLAN_ID="${2:-}"
    [ -z "$PLAN_ID" ] && err "Usage: plan-manager.sh resume <plan-id>"

    FILE=$(plan_file "$PLAN_ID")
    STATUS=$(jq -r '.status' "$FILE")
    [ "$STATUS" != "paused" ] && err "Plan must be paused to resume (current: $STATUS)"

    TMP=$(mktemp)
    jq --arg now "$NOW" '
      .status = "executing" |
      .updated = $now |
      del(.pausedAt)
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    jq '{action: "resumed", id: .id, title: .title}' "$FILE"
    ;;

  list)
    FILTER="${2:---active}"
    case "$FILTER" in
      --active)
        jq -s --arg now "$NOW" '
          map(select(.status | IN("planning","draft","ready","executing","gate","paused"))) |
          sort_by(.created) | reverse |
          map({id: .id, title: .title, status: .status, agent: .agent, created: .created}) |
          {active: length, plans: .}
        ' "$PLANS_DIR"/*.json 2>/dev/null || echo '{"active":0,"plans":[]}'
        ;;
      --all)
        jq -s '
          sort_by(.created) | reverse |
          map({id: .id, title: .title, status: .status, agent: .agent, created: .created}) |
          {total: length, plans: .}
        ' "$PLANS_DIR"/*.json 2>/dev/null || echo '{"total":0,"plans":[]}'
        ;;
      *)
        err "Usage: plan-manager.sh list [--active|--all]"
        ;;
    esac
    ;;

  archive)
    PLAN_ID="${2:-}"
    [ -z "$PLAN_ID" ] && err "Usage: plan-manager.sh archive <plan-id>"

    FILE=$(plan_file "$PLAN_ID")
    STATUS=$(jq -r '.status' "$FILE")
    [ "$STATUS" != "complete" ] && [ "$STATUS" != "rejected" ] && err "Only complete/rejected plans can be archived (current: $STATUS)"

    ARCHIVE_DIR="$PLANS_DIR/archive"
    mkdir -p "$ARCHIVE_DIR"

    TMP=$(mktemp)
    jq --arg now "$NOW" '.status = "archived" | .archivedAt = $now' "$FILE" > "$TMP" && mv "$TMP" "$FILE"
    mv "$FILE" "$ARCHIVE_DIR/"

    echo "{\"action\":\"archived\",\"id\":\"$PLAN_ID\"}" | jq .
    ;;

  card)
    PLAN_ID="${2:-}"
    [ -z "$PLAN_ID" ] && err "Usage: plan-manager.sh card <plan-id>"

    FILE=$(plan_file "$PLAN_ID")
    STATUS=$(jq -r '.status' "$FILE")
    TITLE=$(jq -r '.title' "$FILE")
    PLAN_ID_ACTUAL=$(jq -r '.id' "$FILE")
    AGENT=$(jq -r '.agent' "$FILE")

    DONE=$(count_steps "$FILE" "done")
    TOTAL=$(total_steps "$FILE")
    PCT=$(( DONE * 100 / (TOTAL > 0 ? TOTAL : 1) ))

    # Status emoji and color
    case "$STATUS" in
      planning) EMOJI="📋"; COLOR=5814783; TITLE_PREFIX="Plan Mode Active" ;;
      draft)    EMOJI="📋"; COLOR=5814783; TITLE_PREFIX="Plan Mode Active" ;;
      ready)    EMOJI="📋"; COLOR=16776960; TITLE_PREFIX="Plan: $TITLE" ;;
      executing) EMOJI="🔄"; COLOR=5763719; TITLE_PREFIX="Plan: $TITLE" ;;
      gate)     EMOJI="⏸️"; COLOR=16776960; TITLE_PREFIX="Phase Gate — $TITLE" ;;
      paused)   EMOJI="⏸️"; COLOR=9807270; TITLE_PREFIX="Paused: $TITLE" ;;
      complete) EMOJI="🎯"; COLOR=5763719; TITLE_PREFIX="Plan Complete: $TITLE" ;;
      rejected) EMOJI="❌"; COLOR=15548997; TITLE_PREFIX="Rejected: $TITLE" ;;
      *) EMOJI="📋"; COLOR=5814783; TITLE_PREFIX="$TITLE" ;;
    esac

    # Build description based on state
    DESC=""
    case "$STATUS" in
      planning|draft)
        RESEARCH=$(jq -r '.research | if length > 0 then map("  📄 " + .) | join("\n") else "Gathering context..." end' "$FILE")
        DESC="🔍 Researching: \"$TITLE\"\nAgent: $AGENT\n\n$RESEARCH"
        ;;
      ready)
        PHASE_COUNT=$(jq '.phases | length' "$FILE")
        DESC="📊 $PHASE_COUNT phases • $TOTAL steps\n\n"
        # Build phase list
        DESC+=$(jq -r '.phases[] | "**Phase \(.id) — \(.name)**\(.steps | map("  ⬜ " + .text) | join("\n") | if . != "" then "\n" + . else "" end)"' "$FILE" | sed 's/$/\\n/')
        PENDING_DEC=$(jq '[.decisions[] | select(.status == "pending")] | length' "$FILE")
        [ "$PENDING_DEC" -gt 0 ] && DESC+="\n\nDecisions: $PENDING_DEC pending"
        ;;
      executing)
        DESC=""
        PHASES_JSON=$(jq -r '.phases[] | {id, name, status, steps}' "$FILE")
        DESC+=$(jq -r '
          .phases[] |
          "**Phase \(.id) — \(.name)** " +
          (if .status == "done" then "✅" elif .status == "active" then "🔄" else "⏳" end) +
          "\n" +
          (.steps | map(
            (if .status == "done" then "  ✅ " elif .status == "active" then "  🔄 " else "  ⬜ " end) + .text
          ) | join("\n")) +
          "\n"
        ' "$FILE")
        # Progress bar
        BAR_FILLED=$(( PCT / 5 ))
        BAR_EMPTY=$(( 20 - BAR_FILLED ))
        BAR=$(printf '━%.0s' $(seq 1 $BAR_FILLED 2>/dev/null || echo "") ; printf '░%.0s' $(seq 1 $BAR_EMPTY 2>/dev/null || echo ""))
        [ $BAR_FILLED -eq 0 ] && BAR=$(printf '░%.0s' $(seq 1 20))
        DESC+="\nProgress: $DONE/$TOTAL steps ($PCT%)\n$BAR"
        ;;
      gate)
        GATE_PHASE=$(jq -r '.gatePhaseId // empty' "$FILE")
        PREV_PHASE=$(jq -r --argjson gp "${GATE_PHASE:-0}" '
          .phases[] | select(.id == ($gp - 1)) | .name // "Previous"
        ' "$FILE" 2>/dev/null || echo "Previous")
        NEXT_NAME=$(jq -r --argjson gp "${GATE_PHASE:-0}" '
          .phases[] | select(.id == $gp) | .name // "Next"
        ' "$FILE" 2>/dev/null || echo "Next")
        DESC="Phase $((GATE_PHASE - 1)) complete. Before moving to **$NEXT_NAME**:\n\n"
        DESC+=$(jq -r --argjson gp "${GATE_PHASE:-0}" '
          .phases[] | select(.id == ($gp - 1)) | .steps[] |
          "✅ " + .text
        ' "$FILE" 2>/dev/null || echo "")
        DESC+="\n\nReady for Phase $GATE_PHASE?"
        ;;
      paused)
        DESC="Plan paused. $DONE/$TOTAL steps complete ($PCT%).\n\nUse /plan resume to continue."
        ;;
      complete)
        DESC=$(jq -r '
          (.phases | map("✅ **Phase \(.id) — \(.name)** (\([.steps[] | select(.status == "done")] | length)/\(.steps | length))") | join("\n")) +
          "\n\n\(.phases | [.[].steps[]] | length) steps complete" +
          "\nCreated: \(.created)\nCompleted: \(.completed)"
        ' "$FILE")
        ;;
      rejected)
        REASON=$(jq -r '.rejectReason // "No reason given"' "$FILE")
        DESC="Reason: $REASON"
        ;;
    esac

    # Build buttons based on state
    BUTTONS="[]"
    case "$STATUS" in
      planning|draft)
        BUTTONS=$(jq -n --arg id "$PLAN_ID_ACTUAL" '[
          {"type":2,"style":1,"label":"💬 Discuss","custom_id":"plan-discuss-\($id)"},
          {"type":2,"style":4,"label":"❌ Cancel","custom_id":"plan-reject-\($id)"}
        ]')
        ;;
      ready)
        BUTTONS=$(jq -n --arg id "$PLAN_ID_ACTUAL" '[
          {"type":2,"style":3,"label":"✅ Approve","custom_id":"plan-approve-\($id)"},
          {"type":2,"style":1,"label":"✏️ Modify","custom_id":"plan-modify-\($id)"},
          {"type":2,"style":4,"label":"❌ Reject","custom_id":"plan-reject-\($id)"},
          {"type":2,"style":2,"label":"💬 Discuss","custom_id":"plan-discuss-\($id)"}
        ]')
        ;;
      executing)
        BUTTONS=$(jq -n --arg id "$PLAN_ID_ACTUAL" '[
          {"type":2,"style":2,"label":"⏸️ Pause","custom_id":"plan-pause-\($id)"},
          {"type":2,"style":2,"label":"💬 Discuss","custom_id":"plan-discuss-\($id)"},
          {"type":2,"style":1,"label":"📊 Status","custom_id":"plan-status-\($id)"}
        ]')
        ;;
      gate)
        BUTTONS=$(jq -n --arg id "$PLAN_ID_ACTUAL" '[
          {"type":2,"style":3,"label":"✅ Continue","custom_id":"plan-continue-\($id)"},
          {"type":2,"style":1,"label":"✏️ Revise","custom_id":"plan-modify-\($id)"},
          {"type":2,"style":4,"label":"⏹️ Stop Here","custom_id":"plan-complete-\($id)"}
        ]')
        ;;
      paused)
        BUTTONS=$(jq -n --arg id "$PLAN_ID_ACTUAL" '[
          {"type":2,"style":3,"label":"▶️ Resume","custom_id":"plan-resume-\($id)"},
          {"type":2,"style":2,"label":"💬 Discuss","custom_id":"plan-discuss-\($id)"}
        ]')
        ;;
      complete)
        BUTTONS=$(jq -n --arg id "$PLAN_ID_ACTUAL" '[
          {"type":2,"style":2,"label":"📋 View Full Plan","custom_id":"plan-status-\($id)"},
          {"type":2,"style":2,"label":"📦 Archive","custom_id":"plan-archive-\($id)"}
        ]')
        ;;
    esac

    # Output Discord-ready embed JSON
    jq -n \
      --arg title "$EMOJI $TITLE_PREFIX" \
      --arg desc "$DESC" \
      --argjson color "$COLOR" \
      --argjson buttons "$BUTTONS" \
      --arg planId "$PLAN_ID_ACTUAL" \
      --arg status "$STATUS" \
      '{
        embed: {
          title: $title,
          description: $desc,
          color: $color,
          footer: {text: ("Plan: " + $planId + " • " + $status)}
        },
        components: (if ($buttons | length) > 0 then [{type: 1, components: $buttons}] else [] end),
        planId: $planId,
        status: $status
      }'
    ;;

  set-thread)
    PLAN_ID="${2:-}"
    THREAD_ID="${3:-}"
    [ -z "$PLAN_ID" ] || [ -z "$THREAD_ID" ] && err "Usage: plan-manager.sh set-thread <plan-id> <thread-id>"

    FILE=$(plan_file "$PLAN_ID")
    TMP=$(mktemp)
    jq --arg tid "$THREAD_ID" --arg now "$NOW" '.threadId = $tid | .updated = $now' "$FILE" > "$TMP" && mv "$TMP" "$FILE"
    echo "{\"action\":\"thread_set\",\"threadId\":\"$THREAD_ID\"}" | jq .
    ;;

  set-message)
    PLAN_ID="${2:-}"
    MSG_ID="${3:-}"
    [ -z "$PLAN_ID" ] || [ -z "$MSG_ID" ] && err "Usage: plan-manager.sh set-message <plan-id> <message-id>"

    FILE=$(plan_file "$PLAN_ID")
    TMP=$(mktemp)
    jq --arg mid "$MSG_ID" --arg now "$NOW" '.messageId = $mid | .updated = $now' "$FILE" > "$TMP" && mv "$TMP" "$FILE"
    echo "{\"action\":\"message_set\",\"messageId\":\"$MSG_ID\"}" | jq .
    ;;

  add-research)
    PLAN_ID="${2:-}"
    shift 2
    FINDING="$*"
    [ -z "$PLAN_ID" ] || [ -z "$FINDING" ] && err "Usage: plan-manager.sh add-research <plan-id> <finding>"

    FILE=$(plan_file "$PLAN_ID")
    TMP=$(mktemp)
    jq --arg f "$FINDING" --arg now "$NOW" '
      .updated = $now |
      .research += [$f]
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    echo "{\"action\":\"research_added\",\"finding\":\"$FINDING\"}" | jq .
    ;;

  set-ready)
    PLAN_ID="${2:-}"
    [ -z "$PLAN_ID" ] && err "Usage: plan-manager.sh set-ready <plan-id>"

    FILE=$(plan_file "$PLAN_ID")
    TMP=$(mktemp)
    jq --arg now "$NOW" '.status = "ready" | .updated = $now' "$FILE" > "$TMP" && mv "$TMP" "$FILE"
    jq '{action: "ready", id: .id, title: .title}' "$FILE"
    ;;

  step-active)
    PLAN_ID="${2:-}"
    STEP_ID="${3:-}"
    [ -z "$PLAN_ID" ] || [ -z "$STEP_ID" ] && err "Usage: plan-manager.sh step-active <plan-id> <step-id>"

    FILE=$(plan_file "$PLAN_ID")
    TMP=$(mktemp)
    jq --argjson sid "$STEP_ID" --arg now "$NOW" '
      .updated = $now |
      .phases = [.phases[] | .steps = [.steps[] | if .id == ($sid | tonumber) then .status = "active" else . end]]
    ' "$FILE" > "$TMP" && mv "$TMP" "$FILE"

    echo "{\"action\":\"step_activated\",\"stepId\":$STEP_ID}" | jq .
    ;;

  continue)
    # Alias for advance from gate state — matches the "Continue" button custom_id
    PLAN_ID="${2:-}"
    [ -z "$PLAN_ID" ] && err "Usage: plan-manager.sh continue <plan-id>"

    FILE=$(plan_file "$PLAN_ID")
    STATUS=$(jq -r '.status' "$FILE")
    [ "$STATUS" != "gate" ] && err "Continue is only valid from gate state (current: $STATUS). Use 'advance' from executing."

    # Delegate to advance logic
    exec "$0" advance "$PLAN_ID"
    ;;

  *)
    cat <<'USAGE'
plan-manager.sh — Project plan lifecycle management

Commands:
  create <title> --agent <id> --channel <id>    Create new plan
  add-phase <plan-id> <name> [--gate]            Add phase to plan
  add-step <plan-id> <phase-id> <text>           Add step to phase
  add-decision <plan-id> <q> --options "a,b,c"   Add decision poll
  resolve-decision <plan-id> <dec-id> <answer>   Resolve decision
  approve <plan-id>                              Approve and begin execution
  step-active <plan-id> <step-id>                Mark step as in progress
  step-done <plan-id> <step-id>                  Mark step complete
  advance <plan-id>                              Move to next phase
  modify <plan-id> <change-text>                 Request modification
  status <plan-id>                               Show plan status
  complete <plan-id>                             Mark plan done
  reject <plan-id> [reason]                      Reject plan
  pause <plan-id>                                Pause execution
  resume <plan-id>                               Resume paused plan
  list [--active|--all]                          List plans
  card <plan-id>                                 Generate Discord card JSON
  archive <plan-id>                              Archive completed plan
  set-thread <plan-id> <thread-id>               Set Discord thread ID
  set-message <plan-id> <message-id>             Set Discord message ID
  set-ready <plan-id>                            Mark plan ready for approval
  add-research <plan-id> <finding>               Add research finding
USAGE
    ;;
esac
