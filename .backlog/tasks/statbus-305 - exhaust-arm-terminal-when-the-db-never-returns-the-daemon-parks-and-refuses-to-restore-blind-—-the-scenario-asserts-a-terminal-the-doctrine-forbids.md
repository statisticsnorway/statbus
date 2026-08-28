---
id: STATBUS-305
title: >-
  exhaust-arm-terminal: when the db never returns, the daemon parks and refuses
  to restore blind — the scenario asserts a terminal the doctrine forbids
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-08-28 18:54'
updated_date: '2026-08-28 19:41'
labels:
  - upgrade
  - install-recovery
  - testing
dependencies: []
priority: high
type: task
ordinal: 298000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: decide what the CORRECT terminal state is when the database never comes back — and make the scenario assert that, or build the fallback it assumed. This is the last unattributed red in the campaign; its ruling decides rc.16's promotion.

THE FINDING (rc.16 fleet run 33190460349, transient-db-backoff, mechanic's journal triage — 299 CONFIRMED WORKING first: zero SIGABRT/SIGSEGV/watchdog lines, the bounded sub-attempts logging exactly as designed, daemon alive through the whole 11-minute window): the scenario's EXHAUST arm deliberately never un-pauses the db — its premise is "the db never returns, so the backoff exhausts and the daemon rolls back anyway (data-safe)". The daemon exhausts the budget on schedule, then hits the verify-before-restore doctrine: 'recoveryRollback: upgrade 2 is PARKED (park state UNKNOWN — the read failed (conn closed); refusing to restore on an unverified row) — refusing the automatic rollback'. The row stays parked, the unit alive-idle, the connect loop retrying forever with 299's heartbeat attesting progress. The arm's asserted terminal — rolled_back within 600s — is STRUCTURALLY UNREACHABLE: exhausting the budget and verifying state both depend on the same unavailable resource.

THE QUESTION (architect rules): (a) THE SCENARIO IS STALE — parking is the CORRECT terminal for db-never-returns. Verify-before-restore is the never-destroy-state-under-uncertainty doctrine (the 039/111/159 family); restoring a backup over a database you cannot read is the data-corruption pathway; the designed answer to a permanently-dead db is alive-idle + parked + a human. If so, the fix is the ARM's assertion: expected terminal becomes parked + alive-idle + bounded restarts + the connect loop demonstrably still trying — and the arc then asserts the DOCTRINE rather than contradicting it. (b) A MISSING FALLBACK — a forced, local-only rollback once ALL budgets exhaust and verification is impossible was always intended and does not exist. That is a product build with real data-safety stakes and would need its own careful design (what makes a forced restore safe when nothing can be verified?). (c) Something sharper than either.

EVIDENCE STATUS: not a 299 regression (proven working in the same journal); not a 300-class harness impatience (the failing assertion already retries for its full 600s budget — the db was honestly down the entire time, by the arm's own design). The finding is reproducible by construction: this arm reds every run until the ruling lands.

SEQUENCING: rc.16 is otherwise 36/36. If the ruling is (a), the fix is harness-side (the arm's assertions), the scenario greens on the next run, and rc.16's code is promotable as-is with the arc fix landing on master. If (b), there is a real missing product path and the promotion decision needs the King.

WHAT IS ACHIEVED: the one scenario that has found a bug per layer all campaign either asserts the doctrine correctly or names the fallback the product still owes — and the fleet's verdict becomes fully attributable either way.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (pinned by foreman)
created: 2026-08-28 18:56
---
RULING: (a) — the scenario is stale, and (b) is not a missing path but a path that MUST NOT EXIST. Tested against the convenience of (a) rather than toward it; it survives on THREE INDEPENDENT GROUNDS, any one sufficient. (1) ARITHMETIC, before doctrine enters: rolled_back is a row state in public.upgrade — recording it requires the database the arm stipulates is gone forever; the asserted terminal cannot be written BY CONSTRUCTION. (2) SAFETY, answering (b)'s own question: nothing makes a blind restore safe — from outside the db you cannot distinguish 'gone forever' from 'unreachable right now' (paused container, severed proxy, slow start); a failure to observe is not evidence of absence; if it is merely unreachable but intact, a forced restore writes a backup OVER LIVE DATA — the corruption pathway wearing a recovery costume. The refusal line the journal captured is the product CORRECTLY applying the exact rule this campaign has been enforcing all week — the scenario collided with the codebase doing the right thing. (3) PRECEDENT: STATBUS-111 already decided this — restore-reattempt is human-gated via ./sb install, never the auto service; (b) would REVERSE a ratified ruling. The scenario's premise was not careless — it encoded 'data-safe rollback anyway' BEFORE the 039/111/159 family settled that parking IS the data-safe terminal; doctrine catching up with an assertion.

THE SHARPENING that decides whether the fixed arm proves anything: the four symptom assertions (parked, alive-idle, bounded restarts, still-trying) do not pin the PROPERTY — add the NEGATIVE assertion explicitly: NO restore was attempted over the unverifiable database (the journal's refusal line is its direct positive observation). Without it, a future change that restored blindly AND THEN parked would pass all four. Assert the invariant, not its side effects. Also: bounded-restarts cross-references STATBUS-298 (one arc now guards both); and the arm tests PERMANENT loss under a name that says 'transient' — a comment line in the file, not a rename.

PROMOTION: rc.16's CODE is promotable on evidence in hand — the red is a harness assertion, the code path behaved correctly, every other fix proven live. No product blocker; taking the cheap harness fix + a re-run first (the campaign's first fully green attributable chain) is worth having once — timing is the King's call. IMPLEMENTER: mechanic.
---

author: foreman
created: 2026-08-28 19:11
---
ARM FIX LANDED at 56b6760da (one file, +86/−24). The build's decisive insight, mechanic's own: a target-string swap (rolled_back→parked) in the old helpers would have moved the SAME bug one layer down — all three old assertions were ./sb-psql-based against the db this arm keeps permanently paused. The terminal block is now journal/systemd-only: PARKED marker, refusal reasoning, connect loop demonstrably CYCLING (count ≥ 2, not one stale line — two new arm-scoped journal-count helpers), alive-idle + restarts bounded (STATBUS-298 cross-referenced at the site), and the ruling's NEGATIVE checked LAST across the longest window — exec.go:885's restore-START marker ABSENT, the one assertion a blind-restore-then-park regression cannot pass. VALIDATED against the rc.16 red's own captured journal (all four assertions pass against the real evidence — red-turned-green by construction; connect-attempt count in the capture: 18). ARM 2 untouched and correct as-is (its db comes back, live-query helpers safe) but now inherits a PARKED predecessor from ARM 1 for the first time — flagged, and the LIVE PROOF RUN answers it: targeted dispatch 33202712033 at head 56b6760da, watcher armed. On its green: the campaign's last red becomes a proven assertion of the doctrine, and every scenario in the fleet is attributable.
---

author: foreman
created: 2026-08-28 19:41
---
LIVE PROOF RUN (33202712033): the EXHAUST arm went SIX-FOR-SIX — every new assertion passed live including the negative ('NO restore was ever attempted over the unverifiable database — the invariant holds, not just its side effects', verbatim from the run) — the doctrine assertion is PROVEN. The run then failed at exactly the point the mechanic flagged in his freeze report: ARM 2's opening. Mechanism from the bytes: the same images-ready wait passed at 19:26 (ARM 1, db up) and failed opening ARM 2 at 19:36 with the '?' row-read sentinel — ARM 2's first read ran against the STILL-PAUSED db, because the pre-doctrine rollback used to RESTART the db and ARM 2 always inherited a live one; the parked terminal leaves it paused. One fix remains: ARM 2 opens with db_unpause + a positive wait on the daemon's reconnect (verified against service.go's actual output string, not guessed) before any row read, with the inheritance documented at the arm's header. Mechanic building; on the re-run's green, 305 closes and every scenario in the fleet is attributable.
---
<!-- COMMENTS:END -->
