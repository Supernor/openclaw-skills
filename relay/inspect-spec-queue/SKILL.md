---
name: inspect-spec-queue
description: Relay's protocol for inspecting (read-only), testing existing tests in scratch, writing specs/plans, and queueing changes; plus the routine for when Robert replies to an alert or an error. Use when Robert replies to an alert/error, asks "what is this / look into it / fix it", or asks for a spec or plan.
version: 1.0.0
author: reactor
tags: [inspect, spec, queue, alert, protocol]
---

# inspect-spec-queue (BETA)
BETA (Robert 2026-10-14: "consider it beta like everything else and adjust on the fly"). How to adjust: tell Relay or Reactor. Defaults below are all adjustable.

Runs where: container (Relay, gateway container, user `node`). In-container paths use `~/.openclaw/...` (= `/home/node/.openclaw`); the same files are `/root/.openclaw/...` on the host. Host-only commands (mem, deferred, file-claim, systemctl, docker) do not exist here: dispatch them.
Why this exists: Robert 2026-10-14, "use its given powers for inspection, testing, and spec creation and planning, and still submit its changes to the queue, update Robert, test for Robert, suggest improvements and discuss with Robert". Registry: procedure:relay-inspect-spec-queue.

## Beta defaults
1. Improvement suggestions go to Scribe (skill `workshop`, direction-style, with the evidence), not into chat, unless Robert asked for them in chat.
2. Soft budget: about 5 investigations per day. Past that, ask first ("A) Go ahead B) Hold for tomorrow").
3. Safe-inspection list: no recursive grep/find -exec over `~/.openclaw` (it trips the honeypot canary; target a named file or dir such as `~/.openclaw/logs/<file>`); every DB opened read-only (`sqlite3 -readonly` or `mode=ro`); no tests against the live DB (copy to `/tmp/relay-lab/` first).

## The line
- YOU MAY (via `exec`, READ-ONLY): read logs and files, `sqlite3 -readonly` queries, run existing tests/scripts in scratch (`/tmp/relay-lab/`, never against live data), read the KnownSelf record (`mem_*` tools, `actor="relay"`), write specs/plans (Drive doc, or a file under `/tmp/relay-lab/`).
- YOU MAY NOT: edit live code, config, crons, services, the registry or any of Robert's files; restart anything; run a write query on `ops.db`. Not even when Robert says "just fix it live" or "do it now". Answer: "Changes go through the queue so they are tested and reversible. Queued as task #N." Then do it.

## Queue a change (the one sanctioned path)
`bash ~/.openclaw/scripts/workshop-submit.sh "<what is wrong + evidence (file/row/log line) + proposed fix + Robert's exact words>" <agent> <urgency> "<context: alert id, scar ids>" <host_op>`
-> prints `Task #N created`. host_op: `codex-run` (code fix, default), `reactor-dispatch` (multi-step), `bridge-edit` (Bridge/site), `claude-code-run` (host/infra, only if Robert asked in this chat). Check duplicates first (AGENTS §5). Tell Robert the number. Never claim "fixed" until the task row says done AND you tested it (below).

## When Robert replies to an alert or an error
1. IDENTIFY. Alerts carry an id like `[A-7F3K]`. Robert's reply may quote it, name it, or be a Telegram reply to it (you often will NOT see the alert itself: alerts bypass the gateway). Look it up, read-only:
   `sqlite3 -readonly ~/.openclaw/ops.db "SELECT id,ts,source,severity,text,related FROM alert_log WHERE id='A-7F3K'"`
   No id? list recent: `... ORDER BY ts DESC LIMIT 10`. Not in alert_log? Also try `~/.openclaw/state/alert-log-fallback.jsonl` (written when the DB was locked), then ask Robert for the alert text. One match only: if several could fit, ask a lettered question.
2. LOOK IT UP. `mem_search` / `mem_context_packet` (scars bound to the source script or the error text), `SELECT ... FROM incidents` / `deferred_items` via `ops_query`, and the source's log (`~/.openclaw/logs/`). Cite node ids and log lines.
3. EXPLAIN in four parts: WHAT happened this time · HISTORY (earlier occurrences, what was tried) · NOT TRIED yet · WHAT WORKED before (scar FIX). Plain words, short. If the record does not know, say UNKNOWN.
4. PROPOSE a fix (one recommended, lettered options, A = safest/no change) and OFFER to queue it. Queue only after Robert's letter.
5. AFTER IT LANDS: re-run the original check (read-only) and report the evidence. If it fails, say so plainly.

## Specs and plans
For anything bigger than one fix: write a spec (goal, evidence, steps, rollback, test conditions that define done) as a Drive doc shared to nowthatjustmakessense@gmail.com, then queue it as `reactor-dispatch` with the doc link. Suggest improvements you notice (one line each, with evidence) and discuss; do not build them.

## Rules that stay
Evidence before claims; failed tool call = did not happen; Corinne's silo untouched; fallback model (nemotron) = read/report/queue only. Eoin does NOT get this protocol until Robert says so.
