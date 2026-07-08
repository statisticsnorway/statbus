---
id: STATBUS-149
title: >-
  session-settle-zombie: an advisory-lock holder survives cleanOrphanSessions +
  the 48s settle — blocks the next install at step 10/16 with re-run noise
status: To Do
assignee: []
created_date: '2026-07-08 21:56'
labels:
  - product
  - install
  - sessions
  - investigation
  - install-recovery
dependencies: []
references:
  - cli/cmd/install.go
  - STATBUS-139
  - STATBUS-143
  - tmp/wave2-failed-logs.txt
priority: medium
ordinal: 150000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: `./sb install` never fails its own sessions step on a leftover the machinery is supposed to reap — the settle verdict is either clean or names a cause the operator can act on beyond "re-run".
> BENEFIT: closes the last observed leg of the sessions-step family (STATBUS-139 fixed the single-probe verdict; this is zombie PERSISTENCE through the cleanup itself), seen blocking a real post-upgrade install at step 10/16.
> STAGE: Stage 1. FOUND: wave-2 mid-migration arc, 2026-07-08 (log tmp/wave2-failed-logs.txt), on the post-completion install.
> COMPLEXITY: mechanic investigation FIRST (mechanism unconfirmed — do not presume), then a small fix.
> DEPENDS ON: nothing.

OBSERVED (log-verified): after B's upgrade completed, the arc's next `./sb install` (detectedState=nothing-scheduled, step-table refresh) ran [10/16] Database sessions. Earlier passes in the same run SUCCESSFULLY terminated empty-app_name zombies ("Advisory-lock holder PID 173 (): empty application_name → unidentified zombie → terminating" — likewise PID 312, both followed by DONE), but the final pass FAILED: "database sessions did not settle within 48s after cleanOrphanSessions — 0 leaked migrate backend(s); 1 zombie advisory holder(s) on pid(s) [442]" → install exit 1 with a "re-run ./sb install" message. So the settle logic COUNTED pid 442 as a zombie advisory holder, cleanOrphanSessions ran, and the holder was STILL THERE 48 seconds later.

MECHANISM HYPOTHESES, ranked, for the investigation (map before fix — the 146 lesson: the observed symptom under-determines the mechanism):
(1) TERMINATE-DIDN'T-LAND: the cleanup classifies 442 as zombie but its pg_terminate_backend never fires or fails silently for this classification arm (empty-name zombies demonstrably get terminated; which arm did 442 take — statbus-migrate-<deadpid>? empty? malformed?). The log line for 442's CLASSIFICATION is absent from the extract — pull the full section.
(2) LINGERING BACKEND VIA THE PROXY ROUTE: the arc SIGKILLed the migrate tree earlier; the advisory-lock pgx connection rides the Caddy layer4 DB route (the STATBUS-143 lesson) — the client's death closes the client↔proxy socket, but the proxy↔postgres upstream may linger, leaving a backend holding pg_advisory_lock until TCP timeout — re-appearing as a fresh zombie AFTER each cleanup pass.
(3) PID-RECYCLING FALSE-LEGITIMATE: if 442 came from an app_name statbus-migrate-442 and a LIVE unrelated process now owns pid 442, the liveness check (syscall.Kill(pid,0), install.go:1225-1239) reads it as a legitimate holder and REFUSES to reap — the same PID-is-not-identity class the flag machinery already solved with flocks (service.go:241-244: PID is diagnostic-only).

INVESTIGATION DELIVERABLE: the full mid-migration log section for 442's classification line + the cleanOrphanSessions/settle code walk (install.go:1092-1366) → name the arm 442 took → then the fix shape goes to the architect for ruling. NOTE the composition risk if (3): liveness-by-PID for session reaping is structurally unreliable on any box with PID reuse; the fix direction would be identity-by-more-than-PID (e.g. backend_start vs process start-time, or app_name generation tokens), not a bigger timeout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The mechanism 442 actually took is NAMED from log + code (classification arm, why cleanup didn't remove it), not presumed
- [ ] #2 Ruled fix shipped: the sessions step either reaps the class deterministically or fails naming the actionable cause (never bare re-run noise)
- [ ] #3 Oracle: the mid-migration arc's post-completion install passes step 10/16 on the re-run wave
<!-- AC:END -->
