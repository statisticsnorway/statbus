---
id: STATBUS-159
title: >-
  parked-blocks-fix-claim: a parked row's state='in_progress' blocks the fix
  release from claiming — upgrade_single_in_progress vs the park design
status: To Do
assignee: []
created_date: '2026-07-11 22:36'
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
- [ ] #1 Architect ruling recorded on this ticket: the constraint geometry that lets a fix release claim while a park stands, consistent with 154's parked-cannot-complete invariant
- [ ] #2 A fix release claims and completes while a B row sits parked, proven by the health-park arc C-leg going green on a real box
- [ ] #3 The parked row's final disposition after the fix succeeds is explicit and state-logged (no silent completion of the parked row)
<!-- AC:END -->
