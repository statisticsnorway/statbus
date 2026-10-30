---
id: STATBUS-149
title: >-
  session-settle-zombie: an advisory-lock holder survives cleanOrphanSessions +
  the 48s settle — blocks the next install at step 10/16 with re-run noise
status: Done
assignee: []
created_date: '2026-07-08 21:56'
updated_date: '2026-07-09 00:52'
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
- [x] #1 The mechanism 442 actually took is NAMED from log + code (classification arm, why cleanup didn't remove it), not presumed
- [x] #2 Ruled fix shipped: the sessions step either reaps the class deterministically or fails naming the actionable cause (never bare re-run noise)
- [x] #3 Oracle: the mid-migration arc's post-completion install passes step 10/16 on the re-run wave
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SOURCE FOUND (mechanic static enumeration, 2026-07-09, read-only — no fix built yet). Every advisory-lock acquirer enumerated: migrate.acquireAdvisoryLock (migrate.go:816) tags 'statbus-migrate-<pid>' at :833 — Up/Redo/template-rebuild all covered; migrate.AcquireSeedLock (seed_lock.go:104) tags at :117 and is moot anyway (connects to dbname=postgres; zombieAdvisoryHolders filters a.datname = current_database(), install.go:1295); no SQL-side acquirers in migrations/. THE ONE UNTAGGED ACQUIRER: (*Service).acquireAdvisoryLock (service.go:2368) on d.queryConn — the DSN at service.go:3273-3274 carries no application_name, and internal/upgrade contains zero SET application_name. Mechanism matching the observed cadence exactly: classifyAdvisoryHolder('') unconditionally reads empty app_name as zombie; the service's own LIVE lock connection is killed (PID 173), its next query hits isConnError, d.reconnect() (:3374-3395, ~10 call sites) opens a fresh untagged backend (PID 305/303), misclassified again. Explains the two-per-install-pass kills in the wave-3 arcs, the historical 173→312→442 escalation, and the pre-fix settle-loop timeout — one lock key (upgrade_daemon), one untagged connection, self-regenerating by design. Sharpened finding: the kill-in-loop fix is killing a LIVE self-regenerating connection; the bound of 5 would turn a healthy recognizable holder into regeneratingZombieError. Routed to the architect for the fix-shape ruling: tag both conns 'statbus-upgrade-daemon-<pid>' mirroring the migrate pattern; classification semantics for the new tag and for the empty-string catch-all after it ships; whether the Caddy-route-vs-reaper framing is closed by this.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-08 22:38
---
KILL-IN-LOOP FIX SHIPPED in 46e30276a (2026-07-09) — with an honestly-disclosed process incident: the fix entered master UNREVIEWED because a stash-recovery had staged the two files and the foreman's arc-package commit swept all staged files under a message that did not mention them. The architect's POST-HOC review then PASSED it with zero changes, every ruling pin verified: one kill code path (Phase 2 refactored onto the extracted terminateZombieAdvisoryHolders; the settle loop calls the identical function; no new classification arms; dirty-but-no-zombies correctly gets NO kill), the required bound (pure settleLoopMayKillAgain, trips at N+1, cap 5), the loud regenerating-fail naming totals/attempts/ticket/evidence, per-kill logging with pid + classification so the instrumented run documents the source's cadence free, clean/timeout/error paths preserved. Four tests. The reviewer's honesty note stands on the record: zero cost THIS time was luck (conformant code + an accidental suite cover), and the new CLAUDE.md protocol (coordinator-only git mutation + staged-list check before every commit, 12083f237) is what makes the next occurrence impossible rather than lucky. TICKET STAYS OPEN for the SOURCE question: what generates the empty-app_name advisory-lock zombies (best-supported: the acquirer-rides-Caddy vs reaper-bypasses-it route mismatch) — gated on the wave-3 instrumented run's journal, no speculative route unification.
---

author: foreman
created: 2026-07-08 23:11
---
FIX-SHAPE RULED (architect, 2026-07-09), engineer building: (CORE) tag d.queryConn + d.listenConn with application_name 'statbus-upgrade-daemon-<pid>' in the connect DSN (service.go:3273) — one site covers daemon startup, the inline dispatch's service instance, and every reconnect. (a) classifyAdvisoryHolder mirrors the statbus-migrate-<pid> arm exactly: daemon tag + pid alive → legitimate, skip; tag + pid dead → zombie, kill; NOT routed through the live-upgrade refusal. Key case now correct by design: an idempotent-refresh install with a healthy daemon running was killing the daemon's queryConn on every pass — benign by luck until now. (b) empty-string catch-all KEEPS killing — with migrate, seed, and daemon all tagged, an empty-name holder on our DB is genuinely unidentified; classifier comment gains the known-tag enumeration for future diagnosis. (c) kill-in-loop + bound of 5 + regeneratingZombieError unchanged — with the daemon recognized, the regenerating class returns to genuinely-unknown clients, exactly what the bound exists to catch. (d) ROUTE-MISMATCH FRAMING CLOSED: the mechanism is misclassify → kill → reconnect → fresh untagged backend; zero causal role for the Caddy route — the 'regeneration' was reconnects, not TCP lingering. Oracle: the NEGATIVE marker — healthy installs log zero '→ terminating' advisory-holder lines once the tag ships (the two-per-pass cadence vanishes), riding the next natural arc wave; plus the DSN-tag structural pin and classification-arm unit tests.
---

author: foreman
created: 2026-07-08 23:21
---
SOURCE FIX SHIPPED in 2c258a00c (dual-reviewed: architect ship zero changes, foreman first-hand). recoveryDSN now tags every daemon backend application_name=statbus-upgrade-daemon-<pid> (service.go, one site covering queryConn + listenConn, startup, inline dispatch, every reconnect); classifyAdvisoryHolder gains the mirroring arm (alive→legitimate, dead→zombie, malformed→leave); catch-all keeps killing with the known-tag enumeration in the doc comment; kill-in-loop + bound unchanged as the net for genuinely-unknown clients. The EnsureDBReachable probe sharing the DSN carries the tag too — confirmed correct (daemon-family, never takes the lock). Tests: three classifier cases + TestRecoveryDSNTagsApplicationName source pin. AC#1 and #2 checked. TICKET STAYS OPEN on AC#3 only: the negative-marker oracle — healthy installs log ZERO advisory-holder terminations — requires an arc wave built from a commit containing 2c258a00c; wave 4 (run 28982259924) predates it (built from 08a3c9471, will still show the old cadence — expected, not a failure), so AC#3 lands on the next natural wave.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLOSED on the wave-5 negative-marker oracle (run 28984873852, base b4df4bff2 — the first wave built from a tree containing the 2c258a00c tag fix): ZERO "→ terminating" advisory-holder lines across all four arcs' installs (health-park, working, failing, preswap-checkout-kill — many install passes each), where waves 3 and 4 showed the deterministic two-kills-per-pass cadence on every install. The self-regenerating "zombie" is gone at the source. Full fix history: kill-in-loop + bound (46e30276a) as the interim net — retained permanently for genuinely-unknown clients; source enumeration proving the upgrade service's own connection was the one untagged advisory-lock acquirer; source fix (2c258a00c) tagging every daemon backend statbus-upgrade-daemon-<pid> with the mirroring classifier arm (alive→skip, dead→reap). The route-mismatch hypothesis was closed as wrong (the "regeneration" was the daemon's reconnects after we killed its live connection); the wave-2 sessions-step failure (pid 442 surviving the settle) is fully explained by that loop. The named mid-migration post-completion install (the original AC#3 phrasing) re-confirms for free on that arc's next natural run; the oracle it stood for — the sessions step passing with zero zombie noise — is delivered by this wave's evidence.
<!-- SECTION:FINAL_SUMMARY:END -->
