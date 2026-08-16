---
id: STATBUS-204
title: >-
  budget-park-darkness: the two process-death budget parks bypass
  parkServiceRecovery — route them through the chokepoint so every parked box is
  operable
status: To Do
assignee: []
created_date: '2026-08-16 14:43'
labels:
  - upgrade
  - recovery
  - park
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - >-
    .backlog/tasks/statbus-200 -
    park-outage-a-resource-park-at-the-resumes-pre-pull-check-leaves-the-box-DARK-—-app-rest-stay-stopped-until-the-operator-acts-the-July-14-serve-while-parked-green-was-illusory.md
priority: medium
ordinal: 204000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: same as STATBUS-200 — a parked box is alive-idle AND operable, whatever parked it.
> FOUND: 2026-08-16, architect review of the frozen STATBUS-200 diff. The 200 chokepoint (parkServiceRecovery invoked inside parkForDeterministicFailure) covers every resource/deterministic park site — but TWO callers invoke parkUpgrade DIRECTLY and bypass it: the crash-resume budget/same-step-twice parks (service.go :6818 and :7272 at review time; the flag-based recovery-escalation sites). A box parked by three process deaths keeps the OLD dark behavior: services down until the operator acts.
> SCOPE JUDGMENT (why this is a follow-up, not a 200 amendment): 200's acceptance criteria name the pre-start resource parks, all covered; the budget parks are the same outage class with a rarer trigger; amending a frozen, verified diff mid-cut-window is worse than a clean small unit.

THE FIX: route both sites through the chokepoint (or call parkServiceRecovery directly after their park write). The era guard (parkEraVerdict) already handles their arbitrary box state — post-delta budget parks refuse naturally, pre-delta ones restore. The only real work is CONTEXT THREADING: those sites are flag-based (flag.ID) and need restoreTargetSHA + a *ProgressLog in scope; verify what the flag carries there and thread it. The helper's hard rules carry over unchanged (park write first; only ever starts services; narrative-only on refuse/failure).

ORACLE: extend the STATBUS-200 unit set with a budget-park case (park via the escalation path → parkServiceRecovery invoked; era-refuse narrative on a post-delta state); the postswap-health-park arc's alive-idle assertions remain the VM-level neighbor.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both budget-park sites invoke parkServiceRecovery after their park write, with the era guard deciding; no park site in cli/internal/upgrade bypasses the helper (grep-pinned by unit)
- [ ] #2 A budget-park unit proves the helper is invoked and the era guard's refuse arm narrates on a post-delta state
- [ ] #3 The helper's hard rules hold unchanged: starts-only, narrative-only on refuse/failure, park write first
<!-- AC:END -->
