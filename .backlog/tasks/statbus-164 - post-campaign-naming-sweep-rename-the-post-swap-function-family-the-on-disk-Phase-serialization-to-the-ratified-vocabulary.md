---
id: STATBUS-164
title: >-
  post-campaign-naming-sweep: rename the post-swap function family + the on-disk
  Phase serialization to the ratified vocabulary
status: In Progress
assignee:
  - mechanic
created_date: '2026-07-12 14:05'
updated_date: '2026-07-14 13:04'
labels:
  - clarity
  - de-jargon
  - upgrade
  - recovery
dependencies: []
references:
  - STATBUS-107
  - STATBUS-071
  - doc/upgrade-vocabulary.md
  - cli/internal/upgrade/service.go
priority: low
ordinal: 165000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the last two jargon holdouts — internal Go names and the flag file's stored phase values — speak the ratified plain vocabulary, completing what every reader-visible surface already does.
> STAGE: clarity lane, post-arc-campaign. CARVED FROM: STATBUS-107 at its clean-ship close (2026-07-12) — everything operator- and reader-visible shipped there; these two residuals were deliberately parked and are now an honest To Do instead of a parked In Progress.
> COMPLEXITY: engineer (identifier sweep + a serialization change with cross-version consequences); architect rules the serialization half before build.

THE TWO RESIDUALS, with the original parking rationale (architect, STATBUS-107 comment #2):
1. THE POST-SWAP FUNCTION-FAMILY RENAME — resumePostSwap, applyPostSwap, postSwapFailure, updateFlagPostSwap, writeFlagPhase, IsServiceForwardRecovery + ~250 coupled comment mentions, renamed to the registry slugs (doc/upgrade-vocabulary.md). Parked because "that family is exactly the code the arcs exercise; renaming mid-proof multiplies re-verification cost for a purely internal surface." The arc campaign that justified the park is now substantially complete — build when the remaining map rows are proven or the King prioritizes it.
2. THE ON-DISK PHASE SERIALIZATION — the flag file's stored wire values ("post_swap", "resuming") renamed to the registry slugs. Cross-version recovery consequence: a box mid-upgrade carries the OLD binary's flag that the NEW binary must read. The parked design intent was a CLEAN BREAK (no read-both) + a clean restart on an unrecognized sentinel — safety hinges on restart-safety from a post-swap partial state, which the install-recovery arcs now prove. Architect re-rules the exact shape against the current (145/154/159/163) geometry before any build.

Wire values are byte-identical today (proven by the 107 identifier slice's round-trip tests); nothing is broken — this is the completion sweep, not a fix.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The post-swap function family + coupled comments follow the registry slugs; go build/vet/test green; no wire value changes in this half
- [ ] #2 Architect ruling recorded for the serialization half (clean-break vs read-both, re-derived against the shipped 145/154/159/163 geometry), then built with cross-version recovery proven by an arc
- [x] #3 doc/upgrade-vocabulary.md's one open item (the parked serialization) closes with this ticket
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-13 15:25
---
HALF #1 SHIPPED (foreman commit 6cb5a7652, 2026-07-13): the post-swap function family renamed to registry slugs — resumeNewSb, applyNewSbUpgrading, newSbUpgradingFailure, updateFlagNewSbSwapped, IsServiceNewSbRecovery + coupled constants/test names (30 files, +310/−310, pure 1:1). writeFlagPhase turned out to be a stale comment mention, not a symbol — comment corrected. Foreman independently verified: zero-residual grep, no wire-literal changes in the diff (post_swap/resuming untouched), stray-pipe sweep clean, go build/vet/test all green. AC#1 checked. Mechanic's adjacent observations, deliberately out of scope: (1) needsPostSwapRollback survives only as a string in a must-not-call assertion + history comment (dead, nothing to rename); (2) ~10 prose comments use PreSwap/PostSwap/Resuming as informal phase shorthand — a broader de-jargon sweep if ever scoped; (3) fault-injection scenario names (3-postswap-*) + postswap_test.go filename are a different namespace, untouched. Half #2 (on-disk phase serialization) remains architect-gated per AC#2.
---

author: architect
created: 2026-07-14 10:10
---
RULING part 1/2 (architect, 2026-07-14) — AC#2, serialization half, re-derived against the shipped 145/154/159/163 geometry.

VERDICT: clean-break WRITE + a floor-scoped legacy-alias READ at one typed chokepoint. This deliberately REVERSES the recorded 2026-06-22 clean-restart-on-unrecognized sub-decision — flagged explicitly for the King — because of a decisive fact that decision never had:

THE UNRECOGNIZED-SENTINEL PATH IS MAINLINE, NOT A CRASH CORNER. During the one upgrade that crosses the rename boundary, the OLD binary stamps `"post_swap"` (updateFlagNewSbSwapped, service.go:490) and exits 42; the NEW binary boots and reads those bytes at startup. Every box in the fleet crossing the boundary hits the unrecognized path on its NORMAL handoff — zero crashes required. doc/upgrade-vocabulary.md line 19-20 priced the read as "during crash recovery"; that premise was incomplete.

Why every automatic unrecognized-handler fails on that mainline:
- Today's FLAG_PHASE_UNKNOWN loud-stop (service.go:1162-1167): fleet-wide human intervention on a healthy handoff.
- Classify-then-act (the resuming branch, :986): at the handoff migrations have NOT run → observed state is confirmed-behind → rollback → the boundary upgrade can never complete. Deterministic fleet-wide upgrade blocker.
- Forward-on-unrecognized: works for the handoff but erases the swapped/upgrading distinction for old flags AND permanently disarms the drift guard ("a future writer added a phase without teaching recovery" — the exact fail-loud-touch-nothing case :1162).
- Clean-restart-from-scratch (re-dispatch executeUpgrade): doubles the boundary maintenance window on every box, adds NEW machinery to the proven safety core (new arcs required), and on the crashed-resume × install.sh path a re-run backup would snapshot a PARTIALLY-MIGRATED DB, displacing the true pre-upgrade snapshot the old flag's backup_path points at — a data-safety regression.

PRECEDENT: the wire format already reads historical spellings by design — empty Holder ⇒ service (service.go:233-238), empty Phase ⇒ old-sb-upgrading (:247-251). The alias is the same genre: a COMPATIBILITY FLOOR with a removal condition, not read-both-forever. NSO frame: a broken box's operator runs install.sh, which downloads the NEWEST sb to recover whatever flag is on disk — the newest binary must read every flag spelling still in the field, for as long as pre-rename releases are supported upgrade sources. That is the alias's exact lifetime.
---

author: architect
created: 2026-07-14 10:10
---
RULING part 2/2 (architect, 2026-07-14) — the exact shape:

1. NEW BYTES = the registry slugs VERBATIM (kebab-case): `"new-sb-swapped"`, `"new-sb-upgrading"`. PhaseOldSbUpgrading stays `""` — absence is the value (omitempty), never written, legacy-compatible by construction.
2. WRITERS write only new bytes: the swap stamp (service.go:490) and the resuming stamp (~:6557).
3. READERS: ONE type-level decode chokepoint — UnmarshalJSON on UpgradeFlag (or a single unmarshal helper) used by ALL decode sites: ReadFlagFile (:803), recoverFromFlag's local unmarshal (:898), and the read-modify-write stamps (:487, :535). It normalizes exactly two historical spellings: `"post_swap"`→PhaseNewSbSwapped, `"resuming"`→PhaseNewSbUpgrading. NO raw-byte comparison survives anywhere; the four semantic compare sites (:343, :986, :1084, :1136) are UNTOUCHED — the state machine is unchanged, only the lexer learns two historical spellings, so the arc-proven recovery behavior carries over whole. Rewrites normalize: read old bytes, write new.
4. FLAG_PHASE_UNKNOWN loud-stop STAYS for everything outside the alias table — the drift guard is intact.
5. Alias table carries a grep marker (LEGACY-PHASE-BYTES) + the removal condition (pre-rename releases no longer supported upgrade sources). doc/upgrade-vocabulary.md's parked open item closes with "(legacy bytes: post_swap)" annotations — AC#3.
6. REVERSE-BOUNDARY RESIDUAL, documented not fixed: a crash inside the rollback window after ./sb.old (pre-rename binary) is restored but before flag removal → the old binary reads new bytes → its shipped FLAG_PHASE_UNKNOWN loud stop. Safe (stop, touch nothing), rare (crash inside rollback), unfixable retroactively (shipped binaries). Named in the alias-table comment.
7. HARNESS SWEEP (the 143 all-consumers lesson): fabricate_resume_state writes old bytes (test/install-recovery/lib/data-helpers.sh:502,508) and scenario 4 sed-patches them (4-rollback-abort-write-lands.sh:213-214) — fabrication moves to NEW bytes (it fabricates what the current product writes). Scenario-3/4 prose updated.
8. ORACLE (AC#2 gate): (i) unit round-trips — old-bytes JSON decodes to the typed phases through EVERY exported read path; new bytes idem; junk bytes → FLAG_PHASE_UNKNOWN; IsServiceNewSbRecovery(old-bytes flag)==true, preserving the stalenessGuard carve-out and the checkout gates (root.go:162, install_upgrade.go:228 — the 171 lesson). (ii) ONE cross-version arc: box installed at a pre-rename release, upgrade scheduled to the renamed build — prove the exit-42 handoff resumes forward through the alias read and the row converges completed. That arc is the ruling's run-oracle; no bytes ship to a release before it is green.
9. Go constant NAMES are already correct from half #1 (6cb5a7652); this half changes only the VALUES + adds the decode chokepoint.

Honesty note for the King's ratification: point 3 IS a bounded read-both (write-new, read-old-and-new behind a floor). I rule it because the mainline-handoff fact makes every no-alias variant either fleet-blocking or safety-regressing, and the format already carries two legacy-byte rules of exactly this genre. If the King still prefers literal clean-restart, the ONLY safe variant is: alias for ONE transitional release, then drop — which is the same mechanism with a shorter floor; the mechanism itself has no alternative.
---

author: foreman (relaying King)
created: 2026-07-14 10:17
---
KING RATIFIED the alias ruling (2026-07-14), reversing his 2026-06-22 clean-restart decision on the architect's new fact (the unrecognized read is MAINLINE on the boundary upgrade, not a crash corner), WITH ONE DESIGN REFINEMENT: keep the primary mapping and the legacy aliases as TWO CONCATENATED PARTS — structurally and nominally separate (e.g. the canonical slug table and a clearly-named legacy-alias table joined at the decode chokepoint), so there is no confusion by design and naming. Never one merged map where canonical and legacy spellings are indistinguishable. Build (engineer, after 178): clean-break writers (slugs verbatim), the single UnmarshalJSON-level chokepoint reading canonical-then-legacy from the two named parts, LEGACY-PHASE-BYTES marker + written removal condition, FLAG_PHASE_UNKNOWN guard untouched, harness sweep (fabricate_resume_state + scenario-4 sed), unit round-trips + the ONE cross-version arc (pre-rename box → renamed build, alias resumes handoff, row completed) gating any release that carries the new bytes.
---

author: foreman
created: 2026-07-14 13:04
---
HALF #2 BUILD SHIPPED (foreman commit 0e04a9613, 2026-07-14): writers stamp the registry slugs; ONE UnmarshalJSON chokepoint normalizes the two historical spellings via TWO structurally separate named tables (canonicalPhaseBytes set + legacyPhaseByteAliases map — the King's two-concatenated-parts refinement, verified in review); junk still reaches FLAG_PHASE_UNKNOWN; LEGACY-PHASE-BYTES marker + removal condition + reverse-boundary residual documented in place. Round-trip oracle green (foreman-verified independently): legacy→canonical through every read path, RMW rewrites, IsServiceNewSbRecovery across spellings, tables-disjoint. Harness swept to new bytes (fabricate_resume_state + scenario-4); the restore-broke-reattempt arc's product-written flag assert flipped in the SAME commit (engineer's all-consumers sweep caught it; master self-consistent at every commit). AC#3 checked — doc/upgrade-vocabulary.md's parked item closed. AC#2 remains OPEN until the cross-version arc (pre-rename box → renamed build, alias resumes the handoff, row completed) runs green — engineer building it next; that arc gates any release carrying the new bytes. Soft residual accepted: scenario-3 + rollback-abort-churn still fabricate OLD bytes and pass via the alias — left deliberately as incidental legacy-path coverage.
---
<!-- COMMENTS:END -->
