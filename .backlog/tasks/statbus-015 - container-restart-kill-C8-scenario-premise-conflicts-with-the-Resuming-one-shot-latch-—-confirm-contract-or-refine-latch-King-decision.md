---
id: STATBUS-015
title: >-
  container-restart-kill (C8): scenario premise conflicts with the Resuming
  one-shot latch — confirm contract or refine latch (King decision)
status: To Do
assignee: []
created_date: '2026-06-08 15:33'
labels:
  - install-recovery
  - recovery
  - needs-king-decision
dependencies: []
references:
  - test/install-recovery/scenarios/3-postswap-container-restart-kill.sh
  - cli/internal/upgrade/service.go
priority: medium
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
container-restart-kill (C8 = kill mid-container-restart, between post-swap step 11 and step 12) validated on run 27146230625. The recovery correctly ROLLED BACK with UPGRADE_DIED_DURING_RESUME. Engineer verified (code-proof) this is the Resuming ONE-SHOT LATCH firing — intentional, by design:
- resumePostSwap stamps Phase=Resuming at service.go:4339 BEFORE calling applyPostSwap at :4353. So ALL of applyPostSwap — including step 11, the C8 kill site (service.go:3981) — runs under Phase=Resuming.
- When the first install's C8 kill dies there, the flag is left at Phase=Resuming; the second install reads Resuming → the latch at service.go:755 → recoveryRollback → UPGRADE_DIED_DURING_RESUME, never re-resume.
- This is the intentional anti-infinite-loop contract: "any non-planned restart while in_progress ⇒ died ⇒ rollback." The only legitimate post-swap continue is the PLANNED exit-42 handoff, not a death.

PRODUCT IS CORRECT — 0 confirmed product recovery bugs holds.

THE CONFLICT: the C8 scenario's premise (header lines 9-16) claims "a kill between step 11 and step 12 is recovered by re-running step 11 (idempotent) + step 12 to COMPLETION." That is incompatible with the Resuming latch — there is no post-swap window where a death re-resumes. So the scenario asserts a recovery-to-completion the product (correctly) does not do.

KING DECISION:
- Option 1 (confirm the contract): "Resuming-phase death → rollback" is the intended C8 contract → fix is purely the SCENARIO's assertions (rewrite the premise + Phase 6 to expect rolled_back / UPGRADE_DIED_DURING_RESUME). Quick, contained scenario fix. Engineer's lean.
- Option 2 (refine the latch): distinguish a death at the idempotent step-11/12 window (re-resumable) from a death mid-critical-resume (rollback). Latch REFINEMENT = product change, riskier.

NOTES:
- The team's seed-row fix (necessary) IS confirmed — C8 now dispatches the upgrade + reaches the kill site (it earlier failed at "nothing-scheduled"). 3 real migrations applied (NOT the no-delta/013 family; C8 kills post-migrate, delta-independent).
- The mechanic's 2 parked commits (e1245d697 set-e/pipefail in shared vm-bootstrap.sh; d1a74be6d container-restart-kill set+e) are SUPERSEDED by this verdict — the real fix is the scenario assertions (Option 1), not those. e1245d697 touches the shared helper + is an uncertain separate latent-bug claim → evaluate separately, NOT pushed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 King confirms whether 'Resuming-phase death → rollback' is the intended C8 contract (Option 1) or wants idempotent-step re-resume (Option 2)
- [ ] #2 If Option 1: rewrite C8 scenario premise + Phase 6 assertions to expect the latch rollback (rolled_back / UPGRADE_DIED_DURING_RESUME)
- [ ] #3 If Option 2: latch refinement (product) — distinguish idempotent-window deaths from mid-critical-resume deaths
- [ ] #4 Decide separately whether the mechanic's e1245d697 (install_statbus_in_vm set-e/pipefail) is a real latent bug worth keeping
<!-- AC:END -->
