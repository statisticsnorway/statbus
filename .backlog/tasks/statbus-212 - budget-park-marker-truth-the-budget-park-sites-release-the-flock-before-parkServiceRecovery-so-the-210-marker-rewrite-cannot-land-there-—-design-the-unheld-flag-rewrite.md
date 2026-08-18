---
id: STATBUS-212
title: >-
  budget-park-marker-truth: the budget-park sites release the flock before
  parkServiceRecovery, so the 210 marker rewrite cannot land there — design the
  unheld-flag rewrite
status: To Do
assignee: []
created_date: '2026-08-16 23:00'
updated_date: '2026-08-18 10:01'
labels:
  - upgrade-recovery
  - park
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - >-
    .backlog/tasks/statbus-210 -
    unpark-rollback-collision-the-un-park-grants-a-fresh-attempt-then-flag-based-recovery-classifies-the-same-row-cannot-reach-new-and-rolls-it-back.md
priority: medium
ordinal: 212000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: same as STATBUS-210 — the marker always describes the box; after a source-restoration, EVERY park class carries a truthful pre-swap marker so un-park's fresh attempt is never rolled back by an honest reader of a lying flag.
> FOUND: 2026-08-17, engineer's flock note during the 210 build (correctly not scope-expanded at the night's last freeze; architect ruled follow-up over extension). The 210 fix rewrites the flag via mutateHeldFlag on the era-permitted restoration success arm — which requires the HELD flock. The resource/deterministic park path (applyNewSbUpgrading) holds the flock throughout, so the rewrite lands — tonight's arc-proven coverage. But the STATBUS-204 BUDGET-park sites (RecoveryBudgetGuard, resumeNewSb same-step-twice) release the flock BEFORE parkServiceRecovery runs: there mutateHeldFlag returns "no flag file held", the Warning fires, and the marker stays lying. A budget-parked, source-restored box that is later un-parked hits the SAME collision 210 kills on the main path.

THE DESIGN QUESTION (architect rules before build): how does a non-flock-holding park site truthfully rewrite the marker? Candidates to weigh: (a) briefly re-acquire the flock (LOCK_NB) at the rewrite moment — must reason about who else could hold it at that instant and the failure arm (can't acquire → leave marker, log, accept the stale-marker risk for that box); (b) restructure the budget sites to call parkServiceRecovery BEFORE releasing the flock (ordering change in the escalation path — must not violate the park-write-first pin or the flock's release contract); (c) an unlocked atomic rewrite with its own safety story (rejected on first look — the flock IS the write-serialization for the flag; do not create a second writer discipline). Frequency context: budget park (rare) × un-park (deliberate operator action) — low likelihood, but the collision when it fires destroys a granted attempt, same severity as 210.

ORACLE: extend the 210 unit set — budget-park + restoration success ⇒ marker rewritten (whatever mechanism is ruled); the un-park-after-budget-park story needs at least a structural unit; the arc-level proof rides whichever suite exercises budget parks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect ruling on the unheld-flag rewrite mechanism (re-acquire vs reorder vs other), with the failure arm named
- [ ] #2 The budget-park sites' successful restorations leave a truthful pre-swap marker; unit-pinned
- [ ] #3 No regression to the park-write-first pin, the parked-skip invariant, or the flock contract
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-18 09:50
---
DESIGN RULED — doc-031. The answer is NONE of (a), (b), (c): it is (d) parkServiceRecovery becomes SELF-SUFFICIENT for the flag hold, adopt-or-acquire at the top, release only what it acquired. Same shape as the STATBUS-204 ruling on this same function — the chokepoint owns its invariant. Every premise re-verified at writing time; ONE OF THIS TICKET'S OWN PREMISES DID NOT SURVIVE.

CORRECTION TO THE FILING — (b) WOULD HAVE FIXED HALF THE BUG SILENTLY. The description says both budget sites "release the flock BEFORE parkServiceRecovery". True at site 1 (RecoveryBudgetGuard acquires at service.go:6835, parks, calls release(), then calls the helper at :6920 — a reorder would work). NOT TRUE at site 2: resumeNewSb (service.go:7062) touches the flock EXACTLY ONCE in its entire body, at ~:7434 — AFTER the same-step-twice park branch has already called the helper at :7380 and returned. On that branch the flock was never acquired at all. Nothing to reorder because nothing was released. Had we ruled (b), site 1 would have gone green, the unit would have passed, and site 2 would have kept lying.

WHY (d) AND NOT (a) PER-SITE RE-ACQUIRE. The helper PROMISES truth-restoration (the 210 rewrite at :5882) but can only deliver it when its caller happens to hold the flock — a contract depending on ambient state it neither owns nor checks, which is the drift class the 196 gate hunts and which 204 comment #2 already ruled against for this exact function ("the chokepoint owns its invariant — every-caller-remembers-a-wrapper is precisely the drift class"). (a) re-creates that for every future park site; (d) fixes both budget sites with NO change at either call site, and every future one for free. (c) stays rejected for the reason the filing gives.

MECHANISM, precisely. Already held (`d.flagLock != nil && d.flagLock.file != nil` — the SAME predicate mutateHeldFlag uses at :599-601, not a new one): use it, do not acquire, do not release — the deterministic path stays byte-for-byte unchanged so 210's arc-proven coverage is untouched. Not held: read the current flag, acquire VERBATIM, defer release of exactly that lock. Note for the builder — acquireFlock TRUNCATES AND REWRITES the file with whatever flag value it is handed (:477-487), so a naive acquire clobbers the flag; the house idiom is read-then-acquire-verbatim, which site 1 already performs (`base := *flag`). Extract it as ONE named function rather than a third copy — an acquisition that must not change the flag's meaning should say so at the call site, and the failure arm then lives in one place. No deadlock risk: verified that parkServiceRecovery, parkEraVerdict and restoreSourceServices contain no acquireFlock and no flagLock reference anywhere in their bodies.

AC#1's FAILURE ARM, NAMED: a CONTENDED flock REFUSES THE WHOLE HELPER — narrate and return BEFORE any service is started. Not "restore anyway, skip the rewrite". A live holder IS the liveness signal that another actor owns box mutations (:461-463, STATBUS-111), and starting source services underneath a possible mid-upgrade actor is exactly the mixed-era guess parkEraVerdict refuses on every other anomaly (:5888-5891: "EVERY anomaly REFUSES ... the fail-safe direction is ALWAYS dark-behind-the-maintenance-page"). Near-unreachable in practice — the only realistic contender is ./sb install crash recovery, which quiesces this unit SIGKILL-class before it could hold the lock — but the arm must be correct, not merely rare.

FOLD IN STATBUS-204's OPEN NIT — THIS IS THE "NEXT TOUCH" IT WAS DEFERRED TO (204 comment #3). Site 1 attempts the restoration only if the progress log opens (:6918-6923), so a missing/unopenable log skips the restoration ENTIRELY and the box stays dark for a bookkeeping failure. Degrade to a discard writer: lose the narrative, never the box. Without it, "every park site leaves an operable box and a truthful marker" is still false at site 1 for a second, unrelated reason, and this ticket would close on a half-truth.

ORACLES (AC#2/#3): the 210 unit set extended to assert Phase == PhaseOldSbUpgrading on disk after a budget park + successful restoration at BOTH sites — site 2 is the arm that proves the ruling did more than reorder site 1. A source-parsing pin in the family that already guards this function: the adopt-or-acquire block precedes the era verdict, so a refactor cannot silently drop it (same protection the cover pin gives the watchdog ticker). A pin on the contention arm: no service start when the flock cannot be taken. Structural unit for un-park-after-budget-park; VM proof rides whichever suite exercises budget parks.
---

author: engineer
created: 2026-08-18 09:58
---
**BUILT to doc-031, frozen for review (no commit).** Files: `cli/internal/upgrade/service.go` (+116/-9), new `cli/internal/upgrade/park_flag_hold_test.go`. Ruling (d) realized exactly: the chokepoint owns the flag hold; NO change at either call site.

**The idiom, named once (Finding 3).** `acquireFlockVerbatim(projDir)` at service.go:515 — reads the current flag, hands that exact value back to `acquireFlock` (which truncates and rewrites with whatever it receives), so an acquisition made only to GAIN THE HOLD cannot clobber the marker it exists to protect. One extra guard I added on inspection, not in the ruling: **no flag file ⇒ (nil, nil), never an acquire.** `acquireFlock` opens `O_CREATE`, so a naive call in that state would CONJURE an upgrade-in-progress marker out of nothing — which `./sb install`'s probe would then read as a crashed upgrade. Pinned by its own test arm.

**Adopt-or-acquire, as a named method.** `(*Service).adoptOrAcquireFlagHold()` at service.go:546 returns `(release func(), err error)`. Already held (the same `d.flagLock != nil && d.flagLock.file != nil` predicate `mutateHeldFlag` uses at :599-601, not a new one) → adopt, acquire nothing, **release nothing** (closing a lock this call did not open would pull the flock from under a live `applyNewSbUpgrading`). Not held → acquire verbatim, release exactly that. `parkServiceRecovery` calls it at :5946 with `defer releaseFlagHold()` at :5961, before `parkEraVerdict`.

Why a method rather than an inline block: it makes the ruled behaviour assertable **on disk through production code** rather than through a re-implementation in the test. That is what let the AC#2 oracle be behavioural instead of structural-only.

**AC#1 failure arm, at :5947-5960.** A contended flock refuses the WHOLE helper — `appendParkNarrative` naming the live holder, then return, BEFORE `parkEraVerdict` and before any service start. Never "restore anyway and skip the rewrite": that trades a lying marker for a possibly-mixed-era box.

**AC#2 — on-disk oracles at BOTH sites, all RED-verified.**
- `TestFlagHold_UnheldBudgetPark_RewritesPhaseOnDisk_STATBUS212` — site 2's shape (nothing ever held): adopt-or-acquire → `mutateHeldFlag` → **the bytes on disk** carry `Phase=old-sb-upgrading`, `BackupPath` and identity preserved. It also asserts the mid-state: after acquisition but BEFORE the rewrite the file still reads `new-sb-swapped`, which is the Finding-3 clobber trap pinned directly.
- `TestFlagHold_ReleasedThenAdopted_RewritesPhaseOnDisk_STATBUS212` — site 1's shape, replaying the guard's own acquire/release cycle first.
- `TestFlagHold_AlreadyHeldIsAdoptedNotReacquired_STATBUS212` — the deterministic path: adopted lock is the SAME object, `release()` is a no-op, and the caller's hold still works afterwards. This is what keeps 210's arc-proven coverage valid.
- Plus `NoFlagFileConjuresNothing` and `ContendedFlockIsAnError`.

**RED proof (neutered `adoptOrAcquireFlagHold` to the pre-212 ambient shape):** both on-disk arms fail with the production incident's own words — `the truth-restoration rewrite must succeed once the hold is adopted-or-acquired: no flag file held` — i.e. exactly the Warning today's budget parks print while the marker keeps lying. Restored and green.

**The corrected premise is now pinned so it cannot rot.** `TestBudgetParkSites_EnterWithoutTheHold_STATBUS212` asserts site 2's helper call PRECEDES `resumeNewSb`'s single `acquireFlock` (and that there is exactly one), and that site 1's `release()` precedes its helper call. If someone later "fixes" this by reordering call sites, that test says why it cannot work.

**Structural pin (AC#3), same family as the 204 cover pin:** `TestParkServiceRecovery_OwnsItsFlagHold_STATBUS212` — adopt-or-acquire precedes the era verdict, release is deferred, and the contention refusal precedes both the verdict and `restoreSourceServices`. The pre-existing 200/204/210 pins all still pass unmodified: park-write-first, helper-never-stops, serve-proven ordering, single-park-writer, watchdog cover, and 210's success-arm-only rewrite.

**One risk the ruling did not cover, verified rather than assumed.** The helper now HOLDS the flock across its whole span, so a subprocess inside that span acquiring the same flock would deadlock or fail where it previously would not. Enumerated every acquirer in cli/: the only external one is `./sb install` via `acquireOrBypass` (install.go:179/460). The span's subprocesses are `./sb config generate`, `docker compose start/up`, git, and the health HTTP poll — none touches the flag. No self-deadlock, no new contention.

**Verification:** `go test ./...` in cli/ — 12 packages ok, 0 failures. `golangci-lint run ./...` at 2.12.2 — 0 issues. `gofmt -l` clean on both files (it caught leftover indentation from un-nesting the block that golangci-lint did not — fixed before freezing).
---

author: architect
created: 2026-08-18 10:01
---
REVIEW VERDICT — APPROVED, no amendment. Built to ruling (d) exactly: the chokepoint owns the hold, zero call-site changes, and the deterministic path byte-for-byte unchanged. All three flagged judgments BLESSED; every claim re-verified at source rather than taken from the report.

JUDGMENT 1 — THE (nil, nil) NO-FLAG-FILE ARM: NOT SCOPE CREEP. It closes a hole MY RULING OPENED, and it is the most valuable thing in this diff. I ruled "read the current flag, acquire verbatim" without saying what happens when there is no flag to read. acquireFlock opens O_CREATE (:456), so the naive realization of my own words would CONJURE tmp/upgrade-in-progress.json out of nothing — and per the install state ladder, flag-present + flock-FREE classifies as CRASHED-UPGRADE, whose recovery quiesces the unit and UN-PARKS a parked row. The naive form would therefore have manufactured a marker that causes the next ./sb install to un-park the very row this helper just parked: a fresh instance of the 210 collision, created by the fix for it. Returning (nil, nil) and proceeding without a hold is right — no marker exists, so none can be lying, and there is nothing for the 210 rewrite to correct. Emphatically blessed.

JUDGMENT 2 — NAMED METHOD OVER INLINE: BLESSED, and the SPLIT is better than what I specified. I asked for one named function for the read-then-acquire-verbatim idiom. He wrote two, and the seam is in the right place: acquireFlockVerbatim is the MECHANISM (gain the hold without changing what the flag says), adoptOrAcquireFlagHold is the POLICY (adopt the caller's hold, or take and own one). The mechanism is now reusable by any future caller that needs a verbatim acquire without inheriting the adopt policy, and the policy reads as one legible statement at the chokepoint. His stated reason — the ruled behavior becomes assertable through production code rather than a test-side re-implementation — is sound and is what let AC#2's oracle be behavioral rather than structural.

JUDGMENT 3 — THE NIL-LOG LIVENESS CHAIN: VERIFIED, and it is TIGHTER than he described. Walked every consumer myself. AppendProgressLog returns nil on all three failure shapes — empty relPath (:177), missing file (:181), unopenable (:184) — so the old three-way gate collapses correctly into one nil. Write is nil-guarded before every deref (:241) and its own comment names the consequence: a nil log skips emitHeartbeat. Close (:319), bump (:264), File→io.Discard (:220), RelPath/AbsPath, sinceLastAdvance→0 all nil-safe. The load-bearing one he did not name: shouldPingWatchdog on a nil receiver returns TRUE (:308-311) — a nil log makes the gated ticker ping MORE, never less. And parkServiceRecovery's own ticker already passes nil as its ProgressLog, so the nil-log case was ALREADY the ticker's normal operating mode before this change. Liveness across the span never depended on the log at all; 204's always-ping design is precisely what makes closing its own nit safe. Chain holds.

ALSO CHECKED, unflagged and correct: the contended arm narrates and returns BEFORE parkEraVerdict, so no service is started — the ruled failure arm, to the letter. Defer order is right (LIFO: releaseFlagHold runs before tickerCancel+join, releasing the lock before waiting on the goroutine). The park-write-first pin is intact at site 1 — parkUpgrade, then release(), then the helper. Site 2 is untouched, which IS the proof that ruling (d) did more than reorder site 1. d.flagLock mutation is safe on the daemon's single-flow design; the 204 ticker goroutine never touches it.

ONE CONSIDERED-AND-ACCEPTED NOTE, no action: acquireFlockVerbatim has a read-then-acquire TOCTOU window — another writer could change the flag between ReadFlagFile and acquireFlock, and we would rewrite the stale content. It is closed by the codebase's own discipline rather than by code: every legitimate flag writer holds the flock, and a holder makes our acquire FAIL as contended rather than silently clobber. Same window the existing inline idiom at RecoveryBudgetGuard has always had. Recorded so a future reader does not mistake it for an oversight.

PROCESS POINT — GOFMT AS ITS OWN NAMED STEP: AGREED, fold it into the role docs. golangci-lint at the CI version passed while gofmt did not; a check that catches what the linter misses has earned its own line in the codified chain rather than living in a builder's habit.
---
<!-- COMMENTS:END -->
