---
id: STATBUS-055
title: >-
  migrate-orphan-gate: PID-liveness-aware detection — tagged dead-PID advisory
  holder caught by neither checkSessionsClean branch (bounded recovery delay,
  post-RC)
status: In Progress
assignee:
  - engineer
created_date: '2026-06-15 14:31'
updated_date: '2026-07-03 19:21'
labels:
  - upgrade
  - recovery
  - product
  - follow-up
dependencies: []
priority: medium
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOLLOW-UP (architect finding during STATBUS-029 adjudication, 2026-06-15) — a REAL but BOUNDED recovery weakness; deliberately NOT bundled into this RC.

THE GAP: checkSessionsClean (cli/cmd/install.go:1200-1242) decides whether to TRIGGER cleanOrphanSessions via two counts:
- `leaked`: app IN ('psql','statbus-migrate-sql%') AND a statistical_* query AND query_start < now()-interval '5 minutes' (the 5-min age gate).
- `advisory_holders`: advisory-lock holders with COALESCE(application_name,'')='' (EMPTY app only).
A real killed-migrate orphan = the Go advisory-lock conn tagged `statbus-migrate-<pid>` (acquireAdvisoryLock, migrate.go:297-298) holding migrate_up, PLUS its `statbus-migrate-sql-<pid>` subprocess (migrate.go:303 SubprocessAppNamePrefix) running the statistical_* SQL. A CURRENT-binary tagged advisory holder (`statbus-migrate-<deadpid>`, idle, non-empty app) is counted by NEITHER branch: not `advisory_holders` (non-empty app), not `leaked` (no statistical_* query of its own; the subprocess is a separate session). So a freshly-crashed migration's lock-holder is invisible to the gate until its statistical_* subprocess ages 5min (or forever, if that subprocess already exited) → the next recovery's migrate blocks on the held advisory lock. BOUNDED, not infinite: TCP-keepalive eventually reaps the dead conn, and the 30m migrate timeout bounds the wait — but it is a real multi-minute recovery stall.

THE PRINCIPLED FIX (NOT age-relaxation — that would over-kill live external clients, a regression): make the gate PID-liveness-aware. Count tagged `statbus-migrate-<pid>` advisory holders whose owner PID is dead (the authoritative signal cleanOrphanSessions Phase 2 already uses, install.go:1363+) to TRIGGER the cleanup. The kill stays in Phase 2's PID-probe (already correct); only the GATE's detection needs to learn the tagged-holder shape.

PROOF: its own RED→GREEN — RED: a dead-PID `statbus-migrate-<deadpid>` advisory holder (no aged subprocess) does NOT trigger cleanup → next migrate stalls. GREEN: the gate detects it → Phase 2 probes the dead PID → terminates → migrate proceeds. The re-designed STATBUS-029 (realistic-orphan scenario) may CONFIRM this gap empirically; if so, cross-link.

Scope: cli/cmd/install.go checkSessionsClean. Owner: architect (recovery/session design). Post-RC — bounded weakness, not a wedge; do not rush a gate redesign into the release.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-03 19:04
---
BUILT + FOREMAN-REVIEWED, HELD IN TREE awaiting the architect's design pass, then commit (2026-07-03). Premise verified on HEAD: the gate's two branches (aged leaked-subprocess SQL + empty-app-only advisory SQL) miss a dead-PID statbus-migrate-<pid> holder; Phase 2 could handle it but only runs when the gate already says dirty — and the install.go:1113 comment falsely claimed otherwise (fixed). FIX (as built, 2 files: cli/cmd/install.go +160/-98, cli/cmd/session_orphan_test.go NEW): shared zombieAdvisoryHolders helper (advisory holders → parse tag → syscall PID-probe → classify) used by BOTH the gate and Phase 2 — single source of truth; subsumes empty-app, adds dead-PID-tagged; kill authority stays in Phase 2; fragile t/f output parse replaced; unqueryable state conservatively triggers cleanup; load-bearing SQL comments preserved as Go comments. Foreman full-diff review DONE (positive); all 3 checkSessionsClean callers verified on-host (probe valid, no guard needed); tests green (8-case pure classifier + procAlive + mixed-set). Deterministic reproducer: a session holding pg_advisory_lock(hashtext('migrate_up')) with application_name='statbus-migrate-<dead-pid>' — old gate says clean (RED), new gate says dirty (GREEN); behavioral end-to-end leans on the dev stack + arcs per the package's documented convention. ⚠ The two files sit UNCOMMITTED in the shared tree — any pathspec commit by others must exclude them.
---

author: foreman
created: 2026-07-03 19:21
---
COMMITTED + PUSHED: a3eb522c8 (cli/cmd/install.go + cli/cmd/session_orphan_test.go). Architect design pass: APPROVE AS-IS (shared zombieAdvisoryHolders detection for gate + Phase 2; pure classifyAdvisoryHolder with injected liveness; malformed/subprocess tags left alone; EPERM-as-dead preserved; conservative not-clean on unqueryable state; docker-exec pool-bypass probe). Unit tests green (classifier matrix, procAlive real-dead-PID, mixed sets), go vet clean. Behavioral coverage rides the arc lane: run 28679526112 (dispatched on a3eb522c8) exercises install/upgrade paths that traverse the gate.
---
<!-- COMMENTS:END -->
