#!/usr/bin/env bash
# baton-smoke.sh — Smoke tests for the baton CAS state machine
#
# Tests:
#   1. SUCCESS PATH: required → sending → sent (with attempts=0)
#   2. FAIL PATH: required → sending → required (retry) → sending → sending → failed (dead letter at max attempts)
#   3. CAS GUARD: two workers try to acquire same handoff — only one succeeds
#
# Usage:
#   baton-smoke.sh              # run all tests
#   baton-smoke.sh --success    # success path only
#   baton-smoke.sh --fail       # fail path only

set -eo pipefail

LEDGER_DB="/root/.openclaw/bridge/reactor-ledger.sqlite"
MAX_RETRIES=3

PASS=0
FAIL_COUNT=0

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
pass() { PASS=$((PASS + 1)); log "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); log "  FAIL: $1"; }

sql() { sqlite3 "$LEDGER_DB" "$@" 2>/dev/null; }

smoke_id() { echo "baton-smoke-$(date +%s)-${RANDOM}"; }

get_field() {
  local task_id="$1" field="$2"
  sql "SELECT $field FROM handoff_sent WHERE task_id='$task_id';"
}

# ──── Insert row in 'required' state ────
insert_required() {
  local task_id="$1" ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local changes
  changes=$(sql "
    INSERT OR IGNORE INTO handoff_sent (task_id, status, sent_at, handoff_state, handoff_attempts, handoff_updated_at)
    VALUES ('$task_id', 'done', '$ts', 'required', 0, '$ts');
    SELECT changes();
  ")
  [ "$changes" = "1" ]
}

# ──── CAS: required → sending ────
cas_acquire() {
  local task_id="$1" ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local changes
  changes=$(sql "
    UPDATE handoff_sent
    SET handoff_state = 'sending', handoff_updated_at = '$ts'
    WHERE task_id = '$task_id' AND handoff_state = 'required';
    SELECT changes();
  ")
  [ "$changes" = "1" ]
}

# ──── CAS: sending → sent ────
cas_mark_sent() {
  local task_id="$1" ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sql "UPDATE handoff_sent
    SET handoff_state = 'sent', discord_sent = 1, handoff_updated_at = '$ts'
    WHERE task_id = '$task_id' AND handoff_state = 'sending';"
}

# ──── CAS: sending → required (retry) or sending → failed (dead letter) ────
cas_mark_send_failed() {
  local task_id="$1" error_msg="$2" ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local new_attempts
  new_attempts=$(sql "SELECT handoff_attempts + 1 FROM handoff_sent WHERE task_id = '$task_id';")
  local new_state="required"
  if [ "$new_attempts" -ge "$MAX_RETRIES" ]; then
    new_state="failed"
  fi
  sql "UPDATE handoff_sent
    SET handoff_state = '$new_state',
        handoff_attempts = $new_attempts,
        handoff_last_error = '$(echo "$error_msg" | sed "s/'/''/g")',
        handoff_updated_at = '$ts',
        retry_count = $new_attempts
    WHERE task_id = '$task_id' AND handoff_state = 'sending';"
}

# ──────────────────────────────────────────────
# TEST 1: SUCCESS PATH  required → sending → sent
# ──────────────────────────────────────────────
test_success_path() {
  log "TEST 1: Success Path (required → sending → sent)"
  local tid
  tid=$(smoke_id)

  # Step 1: Insert in required state
  if insert_required "$tid"; then
    pass "insert into 'required' state"
  else
    fail "insert failed"
    return
  fi

  local state
  state=$(get_field "$tid" "handoff_state")
  if [ "$state" = "required" ]; then
    pass "initial state = required"
  else
    fail "initial state = $state (expected required)"
    return
  fi

  # Step 2: CAS acquire (required → sending)
  if cas_acquire "$tid"; then
    pass "CAS required → sending succeeded"
  else
    fail "CAS required → sending failed"
    return
  fi

  state=$(get_field "$tid" "handoff_state")
  if [ "$state" = "sending" ]; then
    pass "state = sending after acquire"
  else
    fail "state = $state (expected sending)"
    return
  fi

  # Step 3: Mark sent (sending → sent)
  cas_mark_sent "$tid"
  state=$(get_field "$tid" "handoff_state")
  if [ "$state" = "sent" ]; then
    pass "state = sent after mark_sent"
  else
    fail "state = $state (expected sent)"
    return
  fi

  local discord_sent
  discord_sent=$(get_field "$tid" "discord_sent")
  if [ "$discord_sent" = "1" ]; then
    pass "discord_sent = 1"
  else
    fail "discord_sent = $discord_sent (expected 1)"
  fi

  local attempts
  attempts=$(get_field "$tid" "handoff_attempts")
  if [ "$attempts" = "0" ]; then
    pass "handoff_attempts = 0 (no retries needed)"
  else
    fail "handoff_attempts = $attempts (expected 0)"
  fi

  # Cleanup
  sql "DELETE FROM handoff_sent WHERE task_id='$tid';"
}

# ──────────────────────────────────────────────
# TEST 2: FAIL PATH  required → sending → required → ... → failed
# ──────────────────────────────────────────────
test_fail_path() {
  log "TEST 2: Fail Path (required → sending → required → ... → failed)"
  local tid
  tid=$(smoke_id)

  insert_required "$tid"

  # Fail MAX_RETRIES times
  local i
  for i in $(seq 1 "$MAX_RETRIES"); do
    # Acquire
    if cas_acquire "$tid"; then
      pass "attempt $i: CAS required → sending"
    else
      fail "attempt $i: CAS failed (state=$(get_field "$tid" "handoff_state"))"
      return
    fi

    # Mark failure
    cas_mark_send_failed "$tid" "Simulated failure #${i}"

    local state attempts
    state=$(get_field "$tid" "handoff_state")
    attempts=$(get_field "$tid" "handoff_attempts")

    if [ "$i" -lt "$MAX_RETRIES" ]; then
      if [ "$state" = "required" ]; then
        pass "attempt $i: back to required (attempts=$attempts)"
      else
        fail "attempt $i: state=$state (expected required)"
        return
      fi
    else
      if [ "$state" = "failed" ]; then
        pass "attempt $i: dead-lettered to failed (attempts=$attempts)"
      else
        fail "attempt $i: state=$state (expected failed)"
        return
      fi
    fi
  done

  # Verify final state
  local final_error
  final_error=$(get_field "$tid" "handoff_last_error")
  if [[ "$final_error" == *"Simulated failure"* ]]; then
    pass "handoff_last_error contains failure reason"
  else
    fail "handoff_last_error = '$final_error' (expected failure reason)"
  fi

  # Verify CAS blocks further acquisition of a failed handoff
  if cas_acquire "$tid"; then
    fail "CAS succeeded on failed handoff (should be blocked)"
  else
    pass "CAS correctly blocked on failed handoff"
  fi

  # Cleanup
  sql "DELETE FROM handoff_sent WHERE task_id='$tid';"
}

# ──────────────────────────────────────────────
# TEST 3: CAS GUARD — two workers, only one wins
# ──────────────────────────────────────────────
test_cas_guard() {
  log "TEST 3: CAS Guard (two workers, only one wins)"
  local tid
  tid=$(smoke_id)

  insert_required "$tid"

  # Worker A acquires
  local a_won=false b_won=false
  if cas_acquire "$tid"; then
    a_won=true
  fi

  # Worker B tries to acquire (should fail — already in 'sending')
  if cas_acquire "$tid"; then
    b_won=true
  fi

  if $a_won && ! $b_won; then
    pass "only worker A acquired the handoff"
  elif ! $a_won && $b_won; then
    pass "only worker B acquired the handoff (A lost)"
  else
    fail "both workers acquired or neither did (a=$a_won, b=$b_won)"
  fi

  # Cleanup
  sql "DELETE FROM handoff_sent WHERE task_id='$tid';"
}

# ──── Main ────
main() {
  log "=== Baton Smoke Tests ==="

  if [ ! -f "$LEDGER_DB" ]; then
    log "ERROR: ledger DB not found at $LEDGER_DB"
    exit 1
  fi

  case "${1:-all}" in
    --success) test_success_path ;;
    --fail)    test_fail_path ;;
    --cas)     test_cas_guard ;;
    all|*)
      test_success_path
      test_fail_path
      test_cas_guard
      ;;
  esac

  log ""
  log "=== Baton Smoke: ${PASS} pass, ${FAIL_COUNT} fail ==="
  if [ $FAIL_COUNT -eq 0 ]; then
    log "VERDICT: PASS"
    exit 0
  else
    log "VERDICT: FAIL"
    exit 1
  fi
}

main "$@"
