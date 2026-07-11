---
id: STATBUS-159
title: >-
  parked-blocks-fix-claim: a parked row's state='in_progress' blocks the fix
  release from claiming — upgrade_single_in_progress vs the park design
status: Done
assignee:
  - engineer
created_date: '2026-07-11 22:36'
updated_date: '2026-07-11 23:48'
labels:
  - upgrade
  - recovery
  - architecture
dependencies: []
references:
  - STATBUS-154
  - STATBUS-145
  - STATBUS-148
  - test/install-recovery/arcs/postswap-health-park-arc.sh
priority: high
ordinal: 160000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a parked upgrade exists precisely to WAIT for a fix release; the fix release must therefore be claimable while the park stands. Today the park itself blocks it.
> STAGE: upgrade recovery / health-park arc. FOUND: 2026-07-12, wave 9 (arc run #54, CI run 29169447311, commit 1710f7dd1) — the arc's first run where all park substance went green and the C-leg exposed this.
> COMPLEXITY: architect ruling REQUIRED — this is constraint geometry at the heart of the state model, and it interacts with STATBUS-154's chk_upgrade_parked_requires_in_progress (parked ⇒ in_progress).

OBSERVED (conviction-grade, daemon journal from 22:09:13, repeating ~20 min):
- B parks correctly: recovery_parked_at SET, both sirens fired, parked-skip boots proven, unit alive. Un-park + re-park with fresh reason + second siren all proven this run.
- C (fix release) scheduled as state='scheduled', id=27.
- Daemon claim of C fails: SQLSTATE=23505, constraint=upgrade_single_in_progress, detail="Key (state)=(in_progress) already exists" → "UPGRADE_CLAIM_FAILED: could not claim scheduled upgrade id=27".
- Arc assertion red: "C (fix release, while B row sits parked with its flag on disk): no terminal state within 1200s".

THE TENSION: upgrade_single_in_progress allows one in_progress row; 154's chk_upgrade_parked_requires_in_progress requires a parked row to BE in_progress (so it cannot be completed out from under its park). Together: while parked, nothing else can ever claim. But the C-leg is the design's whole point — the fix release must proceed over a standing park.

CANDIDATE SHAPES (for the architect to rule, NOT pre-decided): exclude parked rows from the single-in-progress partial index (parked coexists with one live claim), OR the claim path first transitions the parked row to a superseded/terminal state as part of claiming the fix, OR a distinct 'parked' state value with its own invariants. Each moves the state model differently; 154's constraint, the state log, and the parked-skip boot gate all read state directly.

Evidence artifact: upgrade-arc-log-postswap-health-park-29169447311 (14-day retention); operator report has journal excerpts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect ruling recorded on this ticket: the constraint geometry that lets a fix release claim while a park stands, consistent with 154's parked-cannot-complete invariant
- [x] #2 A fix release claims and completes while a B row sits parked, proven by the health-park arc C-leg going green on a real box
- [x] #3 The parked row's final disposition after the fix succeeds is explicit and state-logged (no silent completion of the parked row)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-11 22:45
---
RULED (architect, 2026-07-12) — shape (b): DISPLACEMENT-AT-CLAIM. The claim of a fix release atomically displaces a standing park to an honest terminal, preserving all three invariants (single in_progress; parked ⇒ in_progress; every attempted row reaches a truthful terminal). Verified against the schema first: chk_upgrade_state_attributes requires ONLY superseded_at IS NOT NULL for 'superseded' (doc/db/table/public_upgrade.md:42-53) — error and started_at stay legal, so the displaced row keeps its full story: started_at says 'attempted', error keeps the park reason plus a displacement note. TERMINAL = 'superseded': the causal event IS 'a newer scheduled release took over'; 'failed' is wrong (that state means the attempt itself concluded in failure — B's conclusion was displacement) and it would draw failure-tier attention to an already-sirened park.

THE SHAPE: (1) Consolidate the two duplicate claim sites (service.go:1570 and :4466 — byte-identical claim SQL) into ONE shared claim helper (internal clean-break rule). (2) The helper's ladder, crash-safe by ordering: step A — if a service-held flag exists AND its ID equals the parked in_progress row, remove it (a displaced row's flag is dead weight; removing it FIRST closes the window where a stale flag could route resumePostSwap at a superseded row). Crash after A: B is parked with no flag — no recovery resumes it, daemon runs its normal loop, next claim attempt re-runs the idempotent ladder. step B — one transaction: displace THEN claim. Displacement UPDATE: SET state='superseded', superseded_at=now(), error=COALESCE(error,'') || ' — displaced by <claimant version> claim', recovery_parked_at=NULL, recovery_parked_reason=NULL WHERE state='in_progress' AND recovery_parked_at IS NOT NULL. The WHERE is the guard: a LIVE (unparked) in_progress row matches 0 rows and the claim still hits the 23505 invariant loudly — single-in-progress protection is UNCHANGED for genuinely live upgrades. Parked⇒in_progress + single-in-progress guarantee at most ONE displaceable row exists. Explicit tx, NOT a single CTE statement — a data-modifying CTE the main query doesn't reference has unspecified execution order vs the outer UPDATE's unique-index check. (3) One loud journal line naming the displacement (id, version, park reason, claimant); the 154 upgrade_state_log trigger records the transition (in_progress→superseded, parked→NULL) with the claimant's application_name — the instrumentation audits the displacement for free; the 154 constraint holds by construction (marker cleared in the same UPDATE). No new siren — the park sirened at park time; the displacement is the remedy arriving.

REJECTED: (a) excluding parked rows from the partial index permits TWO in_progress rows and creates a permanent zombie — after the fix completes, nothing ever terminals the parked B (supersede procedures touch only 'available'), and every consumer of 'the in_progress row' (completeInProgressUpgrade, observed-state, UI banner) silently ambiguates. (c) a first-class 'parked' state is the right long-term question but the wrong cost now — a full-surface refactor (enum, chk rewrite, every state consumer, UI legend, tests) duplicating what the marker+invariant pair already expresses; revisit ONLY if parked-marker friction recurs after (b).

ORACLE: wave-10 C-leg re-run — the claim proceeds over the standing park, B lands superseded with reason intact, C runs to its own terminal; the state-log dump shows the displacement row. Also assert B's flag is gone and C wrote its own. Residual noted, NOT this ticket: markCurrentVersionCompleted's binary+migrations gate could later complete a superseded-displaced row whose sha matches HEAD after a C rollback returns the box to B's binary — pre-existing class (gate ignores app health), same before/after this fix; file separately if it ever fires.
---

author: architect (via foreman)
created: 2026-07-11 22:56
---
Dump-rider corroboration (architect, 2026-07-12, tmp/wave9-healthpark-job.log): ruling stands UNCHANGED after reading the primary evidence. The five upgrade_state_log records narrate B's entire lifecycle gaplessly (available→scheduled atomic reschedule; scheduled→in_progress via the :4466 claim; park; un-park via UnparkByID; re-park), each tagged with daemon application_name + backend pid + verbatim statement — and NOTHING after the 22:07:49 re-park during the 20 min of C-claim failures. That absence proves both: (1) the 154 fix held — markCurrentVersionCompleted's guarded UPDATE matched 0 rows silently, no completion steal; (2) the C-leg blocker is PURELY constraint geometry — no second bug behind it. The invisible-writer class is dead: any future state mutation appears named in this log. Displacement ladder's exact input state confirmed: B id=18, in_progress, parked=t, service-held flag pointing at id=18 with phase=resuming/step=health-check (flag survives the park untouched, as designed) — precisely what step A's guarded flag removal and step B's displace-then-claim consume.
---

author: foreman
created: 2026-07-11 22:59
---
RULING AMENDMENT (architect confirm, 2026-07-12): the two claim sites' MUTATING clause is byte-identical as ruled, but the RETURNING projections differ (service.go:1570 returns commit_tags+recreate; :4466 returns recreate only, sourcing commit_tags from the earlier pending-row SELECT at :4415). Engineer stopped on the named condition instead of adapting — correct. Confirmed shape: the shared claim helper uses the superset RETURNING (commit_tags, recreate); site 2 takes commit_tags from the helper's return. Strictly better than the old shape: the value now comes atomically from the claim UPDATE, closing the stale-read window between :4415's SELECT and the claim. Pending-row SELECT keeps commit_sha/scheduled_at/docker_images_status for the claim gate + displayName. Displacement ladder unchanged. Build proceeding.
---

author: foreman
created: 2026-07-11 23:21
---
SHIPPED: 2581d71da (2026-07-12). Architect verdict SHIP after two review fixes: (1) both call sites take commit_tags from the claim's atomic RETURNING + displayName recomputed post-claim from the claimed tags (the mandatory part landed in the first amendment; the displayName recompute was architect-waived as cosmetic but applied anyway); (2) displacer identity corrected — the displacement note and loud line name the CLAIMING row's id, not d.version (which is the running binary = the displaced row itself post-swap; it would have named itself as its own displacer). Review also confirmed a property better than the ruling asked: the displacement rides the claim's transaction, so a failed claim rolls the displacement back — a park is never consumed without a successful takeover. Verification: go build/vet, gofmt, the 092 durability test green; arc bash -n + shellcheck clean. WAVE 10 dispatched to the operator on 2581d71da — its C-leg is the oracle for ACs #2/#3.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SHIPPED 2581d71da; PROVEN by wave 10 (arc run #55, CI run 29171998401, 2026-07-12) — the health-park arc's first full end-to-end green. C (a genuine fix release, new migration V3) claimed OVER B's standing park via displacement-at-claim: B landed state='superseded' with the park reason AND the displacement note intact in error (AC#3 — explicit, state-logged disposition: the upgrade_state_log shows exactly one in_progress→superseded, parked→NULL row); B's stale flag was removed by the claim ladder's step A; C completed at t+66s with data intact (AC#2). The fix: claimScheduledUpgrade consolidates both claim sites; crash-safe ladder (flag removal first, then one explicit displace+claim transaction — a failed claim rolls the displacement back, so a park is never consumed without a successful takeover); a live unparked in_progress row matches the displacement WHERE on zero rows, keeping single-in-progress protection unchanged. Full ruling comment #1; dump-rider corroboration #2; review amendments #3/#4. Residual filed separately: STATBUS-160 (superseded-cannot-complete).
<!-- SECTION:FINAL_SUMMARY:END -->
