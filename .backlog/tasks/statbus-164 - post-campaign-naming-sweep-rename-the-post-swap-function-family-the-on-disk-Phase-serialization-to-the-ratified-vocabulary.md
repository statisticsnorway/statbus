---
id: STATBUS-164
title: >-
  post-campaign-naming-sweep: rename the post-swap function family + the on-disk
  Phase serialization to the ratified vocabulary
status: In Progress
assignee:
  - mechanic
created_date: '2026-07-12 14:05'
updated_date: '2026-07-13 15:13'
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
- [ ] #1 The post-swap function family + coupled comments follow the registry slugs; go build/vet/test green; no wire value changes in this half
- [ ] #2 Architect ruling recorded for the serialization half (clean-break vs read-both, re-derived against the shipped 145/154/159/163 geometry), then built with cross-version recovery proven by an arc
- [ ] #3 doc/upgrade-vocabulary.md's one open item (the parked serialization) closes with this ticket
<!-- AC:END -->
