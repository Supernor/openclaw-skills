---
name: backup-audit
description: How Failsafe judges the weekly backup beat from PUSHED receipts — interpretation table, thresholds, and the coverage-gap question technique. Use every weekly beat.
---

# backup-audit

You judge PUSHED text only. You do not run restic, sqlite3, or any command — the
host executor already ran `failsafe-receipts.sh` and gave you its `key: value`
block. Your job is to read it and deliver VERDICT / FLAGS / one COVERAGE-GAP question.

## Golden rule
A backup that has NOT been restore-tested is UNVERIFIED, not healthy. When in doubt,
say UNKNOWN. A false "PASS" is the most expensive thing you can output — it tells
Robert he is safe when he may not be.

## Interpretation table — what each receipts line means

| receipts key | meaning | PASS-shaped | FAIL / escalate |
|---|---|---|---|
| `r2-backup-state` | last nightly backup result in kv | `ok <recent ts>` | `failed: ...` or ts old |
| `r2-backup-age-days` | deterministic age of last nightly backup | <= 2.0 | > 2.0 = FAIL; UNAVAILABLE = UNKNOWN |
| `r2-backup-log-1..3` | tail of the backup log | ends `=== r2-backup OK ===` | shows `FAIL:` |
| `restic-snapshot-count` | snapshots in R2 repo | >= 2 | 0, or UNAVAILABLE |
| `restic-opsdb-snapshot-age-days` | age of newest snapshot **for the ops.db.snapshot path** | <= 2.0 | > 2.0 = FAIL (the restorable DB copy is stale) |
| `restic-openclaw-snapshot-age-days` | age of newest snapshot **for the /root/.openclaw tree** | <= 2.0 | > 2.0 = FAIL |
| `restic-repo-raw-size-gb` | raw data size in repo | < 8.0 | 8–10 warn, >10 FAIL (over tier) |
| `restic-tier-headroom-gb` | 10GB tier minus size | > 2.0 | <= 2.0 = warn approaching tier |
| `failsafe-drill-state` | last restore-drill result | `ok <ts> nodes=.. edges=.. tasks=..` | `failed:` or absent |
| `failsafe-drill-age-days` | age of last drill | <= 10.0 | > 10 = UNKNOWN-must-escalate |
| `failsafe-drill-log-1..2` | INDEPENDENT tail of the drill log | ends `restore-drill OK` | shows `FAIL:` (trust over kv if they disagree) |
| `local-backups-size` | on-disk backups/ size | present, sane | UNAVAILABLE (noncritical) |
| `local-backups-newest-artifact-age-days` | freshness of real local artifacts (ops-*.db*/*.snapshot) | <= 2.0 | old = stale local copy |
| any line = `UNAVAILABLE (...)` | a probe could not answer | — | never PASS on it — UNKNOWN |

Note: the two snapshot ages are per-path and host-bound on purpose — a recent
UNRELATED snapshot can NOT satisfy the ops.db requirement. Judge each path on its own.

## Thresholds (hard rules)
- backup older than 2 days -> **FAIL**
- restore drill older than 10 days (or missing) -> **UNKNOWN — must escalate**
- repo over 8GB -> **warn: approaching 10GB tier**; over 10GB -> **FAIL**

## The absolute UNAVAILABLE rule
ANY receipts line whose value is `UNAVAILABLE (...)` forces VERDICT **UNKNOWN**, not
PASS — no exceptions, no "probably fine". You do not get to decide a probe was
optional. The ONLY receipts keys whose UNAVAILABLE is noncritical (may stay PASS if
every OTHER signal is green) are exactly these:
- `local-backups-size`
- `local-backups-newest-artifact-age-days`
- `restic-repo-raw-size-gb` / `restic-tier-line-gb` / `restic-tier-headroom-gb` (tier
  headroom is a cost signal, not a recoverability signal)
UNAVAILABLE on anything else — the two snapshot ages, backup state/age, the drill
state/age/log, snapshot count — is UNKNOWN, always.

## Verdict decision order
1. Any `FAIL`-shaped line above -> VERDICT FAIL.
2. Else any UNKNOWN trigger (UNAVAILABLE, drill >10d/missing) -> VERDICT UNKNOWN.
3. Else all recent + drill proved restorable -> VERDICT PASS.
Always print the numbers you judged on so a human can check you.

## Coverage-gap question technique
Each beat, name ONE thing that would be lost forever if the VPS died right now —
something that lives in exactly one place and is not in git and not in R2. Phrase it
as an actionable question for Reactor/Captain. If nothing is exposed, say
`NONE` and say why (what channels independently hold each critical asset).

Worked examples:
1. Receipts show `restic` excludes `logs/` and the drill only covers `ops.db`.
   -> "Coverage gap: are the R2 credentials in `.r2.env` and the restic password file
   themselves backed up anywhere? If R2 is our only offsite copy, losing the VPS
   loses the key needed to read R2 — a circular dependency. Where is the second copy?"
2. Receipts show `local-backups-newest-file-age-days: 9.3` while R2 snapshot age is
   0.5. -> "Coverage gap: local `backups/` is 9 days stale — if R2 auth breaks we fall
   back to a 9-day-old local copy. NONE lost today, but the fallback window is aging.
   Should the local mirror run more often?"
3. All receipts green, drill fresh. -> "NONE today: ops.db is proven-restorable from
   R2 (drill 1d old), code lives in git (Repo-Man's domain), and local `backups/`
   is 1d old. Three independent channels, no shared failure domain I can see. Open
   question for Captain: is any NEW subsystem writing state outside ops.db + git?"

## What you never do
- Never print credentials or the restic password (the receipts already omit them; keep it that way).
- Never mark PASS to be reassuring. UNKNOWN is a valid, honest, useful answer.
- Never invent a number the receipts did not give you.
