---
name: stable-release-watch
description: Assess a newer OpenClaw STABLE release and recommend land-or-hold to Robert. Distinct from upstream-check (which watches OUR PR activity); this watches OpenClaw's stable release tags.
version: 1.0.0
author: repo-man
tags: [github, openclaw, updates, releases, monitoring]
---

# stable-release-watch

## Purpose
You (Repo-Man) own watching for newer **stable releases of OpenClaw** and telling
Robert whether to land one. A zero-cost cron (`openclaw-stable-watch.sh`) does the
detection and alerts on a new stable; your job is to **assess and recommend** — you
do NOT run the update yourself (it is a host operation and is confirm-gated).

> Context you need: OpenClaw is the fastest-growing repo in GitHub history,
> ~535 commits/day, **mostly AI-authored by design** (creator: Peter Steinberger /
> `steipete`). We track STABLE releases, not bleeding-edge `main`. Read once:
> `cat /root/.openclaw/update/UNDERSTANDING-OPENCLAW-UPDATES.md`.

## When to use
- The `openclaw-stable-watch` cron alerted that a newer stable is out.
- Robert asks "should we update?" / "any new OpenClaw release?"
- `kv` key `openclaw_update_status` shows `newer_available=true`.

## Steps

### 1. Read current status (no new call needed — the cron wrote it)
```
kv: openclaw_update_status   (running vs newest_stable vs newer_available)
file: /root/.openclaw/openclaw-stable-watch-state.json
```

### 2. Re-verify if you want a fresh comparison
Request a host check (you can't run host Docker). Queue a task with
`meta = {"host_op":"openclaw-update","op":"check"}`; the executor runs
`update.sh --dry-run` host-side and returns the running-vs-stable delta + the
no-downgrade decision. (`op=check` is always safe.)

### 3. Review what changed — with the AI-blindspot lens
The new stable's commits are mostly AI-authored, so review them like AI code, not
human code. Pull the release notes / changelog for the new tag (you have GitHub
access) and look hard for the risky classes: config/migration changes, security
(auth, injection, secrets — OpenClaw has full system access), removed fallbacks,
breaking API/flag changes. Chart-search the lessons first:
`ref-openclaw-update-understanding`, `reading-ai-code-blindspots`,
`reading-update-build-oom`, `ref-update-test-suite`.

### 4. Recommend to Robert (via Captain) — land or hold
Report: current version, the new stable version, the notable changes, your risk read,
and a clear **land / hold** recommendation. Remember the update is fully gated
(hash-gated before/after test, auto-rollback) so "land" is low-risk if it passes —
but a holiday/low-attention window is a reason to hold.

### 5. If Robert says land
The update runs host-side via the gated `openclaw-update` handler with
`meta.confirm=true` (Robert or Reactor confirms — you do not run it). It stops the
gateway, builds, recreates, runs the post-test, and auto-rolls-back on regression.

## Hard rules
- Detect/assess/recommend only — **never run the update** (needs confirm + host Docker).
- Never recommend a downgrade. If running version >= newest stable, there is nothing to do.
- Report to Captain, never directly to Robert.
