---
id: STATBUS-204
title: >-
  budget-park-darkness: the two process-death budget parks bypass
  parkServiceRecovery — route them through the chokepoint so every parked box is
  operable
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-16 14:43'
updated_date: '2026-08-16 18:17'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-16 18:17
---
BUILD HELD — WATCHDOG-COVER FINDING (engineer pre-build byte-walk, 2026-08-16; ruling pending with the architect): the filing's 'context-threading is the only work' premise understates it. Both budget-park sites (process-death in RecoveryBudgetGuard ~:6831, same-step-twice in resumeNewSb ~:7286 on current HEAD) run in systemd's ACTIVE phase (READY=1 at :1999) with NO gated watchdog ticker in their span — and parkServiceRecovery's slow work (StartDBForRecovery ≤60s + compose up + healthCheck ≤25s + restores) can exceed WatchdogSec=120 on a cold box → SIGABRT → crash loop at the very park the fix makes operable (the 195 doctrine applied). The deterministic sites are covered by their CALLERS' outer tickers (:6107, :3115); the budget sites have none. Site 1 also lacks a ProgressLog (log.Printf only) — threading via loadLogRelPath + AppendProgressLog. SHAPES AWAITING RULING: (A) per-site runGatedWatchdogTicker wraps — localized, leaves committed 200 code untouched; (B, engineer-recommended, foreman-concurred) parkServiceRecovery becomes SELF-covering — the gated ticker wraps restoreSourceServices internally, covering deterministic sites (harmless nested ticker), budget sites, and every future caller at the one chokepoint (the same close-the-invariant shape ruled on 200 Q4 and 197 C3). Either shape ships with the RED-first unit pinning both sites call the helper AFTER their park write, plus the site-1 log threading.
---
<!-- COMMENTS:END -->
