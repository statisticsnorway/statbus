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
updated_date: '2026-08-16 18:24'
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
- [x] #1 Both budget-park sites invoke parkServiceRecovery after their park write, with the era guard deciding; no park site in cli/internal/upgrade bypasses the helper (grep-pinned by unit)
- [x] #2 A budget-park unit proves the helper is invoked and the era guard's refuse arm narrates on a post-delta state
- [x] #3 The helper's hard rules hold unchanged: starts-only, narrative-only on refuse/failure, park write first
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-16 18:17
---
BUILD HELD — WATCHDOG-COVER FINDING (engineer pre-build byte-walk, 2026-08-16; ruling pending with the architect): the filing's 'context-threading is the only work' premise understates it. Both budget-park sites (process-death in RecoveryBudgetGuard ~:6831, same-step-twice in resumeNewSb ~:7286 on current HEAD) run in systemd's ACTIVE phase (READY=1 at :1999) with NO gated watchdog ticker in their span — and parkServiceRecovery's slow work (StartDBForRecovery ≤60s + compose up + healthCheck ≤25s + restores) can exceed WatchdogSec=120 on a cold box → SIGABRT → crash loop at the very park the fix makes operable (the 195 doctrine applied). The deterministic sites are covered by their CALLERS' outer tickers (:6107, :3115); the budget sites have none. Site 1 also lacks a ProgressLog (log.Printf only) — threading via loadLogRelPath + AppendProgressLog. SHAPES AWAITING RULING: (A) per-site runGatedWatchdogTicker wraps — localized, leaves committed 200 code untouched; (B, engineer-recommended, foreman-concurred) parkServiceRecovery becomes SELF-covering — the gated ticker wraps restoreSourceServices internally, covering deterministic sites (harmless nested ticker), budget sites, and every future caller at the one chokepoint (the same close-the-invariant shape ruled on 200 Q4 and 197 C3). Either shape ships with the RED-first unit pinning both sites call the helper AFTER their park write, plus the site-1 log threading.
---

author: architect
created: 2026-08-16 18:18
---
WATCHDOG-COVER RULING (architect, 2026-08-16; the engineer's find is real and the hold was right again — the budget sites run post-READY in the active phase with no outer gated ticker, and the helper's slow span can exceed WatchdogSec=120 on a cold box; shipping 204 without cover would convert the fix into a SIGABRT crash loop at the very park it makes operable, violating the 195 doctrine it sits under).

RULED: (B) — parkServiceRecovery becomes SELF-COVERING, with one widening: the internal gated ticker must span the helper's WHOLE slow span, not only restoreSourceServices — parkEraVerdict's StartDBForRecovery (up to ~60s) is inside the span and precedes the restore. Put the ticker at the top of parkServiceRecovery, covering verdict + restoration together. Rationale, same shape as 200 Q4 and 197 C3: the chokepoint owns its invariant — a helper that does slow work owns its own liveness cover; every-caller-remembers-a-wrapper is precisely the drift class the 196 gate exists to hunt, and (A) would re-create it for every future caller. The nested ticker at the deterministic sites is harmless (two layers both emit WATCHDOG=1 — extra pings, no interference).

DOCTRINE NOTE so the always-ping-vs-per-unit question does not reopen: 195's rule is 'kill hung daemons, never slow-but-live ones', enforced by feeding per unit of genuine progress. An ALWAYS-PING ticker is legitimate here because every sub-step in the covered span is itself TIME-BOUNDED (StartDBForRecovery's bound, compose-up's command timeout, healthCheck's bounded attempts) — a genuine hang cannot hide behind the ticker beyond the bounds' sum, exactly the boot-migrate precedent (its own always-ping ticker bounded by MigrateUpTimeout). Cover-with-bounds is hang-detection by construction.

ALSO APPROVED: the site-1 ProgressLog threading via loadLogRelPath + AppendProgressLog (a park narrative belongs in the row's own progress log, not the journal). Editing the committed 200 helper is a normal forward change under review, not a reversal — the helper's contract gains cover, existing behavior otherwise unchanged. ORACLES: the RED-first unit pinning both budget sites calling the helper AFTER their park write (as planned) + a cover pin in the source-parsing family: the ticker wrap is present inside parkServiceRecovery and precedes the verdict call (so a future refactor cannot silently drop the cover). Build proceeds on this comment.
---

author: foreman
created: 2026-08-16 18:24
---
BUILT + ARCHITECT-APPROVED + COMMITTED ccf86fe3c (foreman, 2026-08-16). Ruling (B)-widened realized to the letter: the always-ping gated ticker sits at the TOP of parkServiceRecovery spanning the era verdict's DB wait AND the restoration, defer cancel+join so it never outlives the helper, with the bounded-sub-steps justification written into the comment; both budget sites route through the chokepoint AFTER their park write (site 1 threads a progress log via loadLogRelPath+AppendProgressLog with DB-up/flock justifications in place; site 2 rides its existing log); restoreTargetSHA="" correctly rides the post-197 identity. All three criteria CHECKED: the every-parkUpgrade-caller-must-route drift pin (a future bypassing park site fails the unit until routed — the 196 philosophy applied to park topology), the era-refuse narrative covered by the existing source-identity unit, the helper's hard rules intact. Foreman verification pre-commit: build/vet/gofmt clean, both 204 oracles green under my execution, full upgrade package green. ONE NIT recorded for the next touch, non-blocking (architect): site 1's missing/unopenable progress log currently SKIPS the restoration attempt (safe pre-204 degradation, row narrative still lands) — next touch degrades to a discard-writer log instead of skipping; rare edge, every dispatched row records a log path at claim. VM-level neighbor (postswap-health-park alive-idle asserts) rides the next suite dispatch. WITH THIS COMMIT THE KING-AUTHORIZED RIDE-ALONG QUEUE IS CODE-COMPLETE: 202+amendment, 201, 200, 199, 197, 203, 204 — seven tickets, every diff reviewed, every ruling on its ticket; the board's remaining opens are observation criteria only the King's cut and the arc suite at its tag can check.
---
<!-- COMMENTS:END -->
