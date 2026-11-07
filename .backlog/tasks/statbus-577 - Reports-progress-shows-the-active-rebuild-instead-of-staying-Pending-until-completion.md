---
id: STATBUS-577
title: >-
  Reports progress shows the active rebuild instead of staying Pending until
  completion
status: In Progress
assignee: []
created_date: '2026-11-07T19:56:00Z'
updated_date: '2026-11-07T20:37:00Z'
labels:
  - frontend
  - worker
  - progress
dependencies: []
priority: high
type: bug
ordinal: 504204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner observed Norway run B on v2026.11.2-rc.02: Statistical Units shows percentage progress, while Reports remains Pending with ~24000 legal units/enterprises and then disappears. Read-only SQL at 2026-11-07 19:55:43Z returned public.is_deriving_reports active=true, step=statistical_unit_facet_reduce. Trace database phase notifications, SSE delivery and navbar state. Preserve the active benchmark and do not change Norway during import.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A regression reproduces the observed pending-to-active-to-completed reports lifecycle and fails before the fix.
- [ ] #2 The navbar displays the actual active reports step and its available progress, while correctly distinguishing waiting for unit derivation from running reports.
- [ ] #3 Relevant SQL/frontend tests and exact-SHA CI pass; the candidate browser workflow visibly transitions through running reports to completion.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07 20:14 UTC:
- Owner screenshots and read-only Norway SSE capture reproduce Reports remaining Pending while the database runs statistical_unit_facet_reduce.
- Frontend RED 198de2714 and GREEN 6fcd19bf5 cover queued -> boolean start -> detailed current step -> idle, preserve queued reports during units, and preserve structured progress on a later start event.
- Backend RED 1e9a5d946 and GREEN 90ba625d2/test391 prove that worker.process_tasks publishes each depth-2 running step before invoking its handler. The forward migration adds only the notifier call before the existing start-state COMMIT.
- A disposable database down/up round-trip reproduces the defect then restores expected output. Native LISTEN/NOTIFY proof observes 10 committed events, both running reducer steps before handler completion, then reports idle (tmp/577-committed-notification-proof.log).
- Complete doc/db regeneration leaves only the intended procedure doc change and records clean source 20261107200300. Frontend 25 suites/208 tests, tsc and lint passed (0 errors, 5 existing warnings). Coordinator reran lifecycle tests/tsc and the production build.
- Full format check reports 245 style warnings. The modified worker file also fails on its pre-fix definition, while the new regression test formats cleanly. This is not a claim of a passing full format check.
- Final combined SQL fast is running via tmp/test-577-fast-run.sh, with its real exit saved separately. The advertised detached wrapper dropped the subcommand, so its launcher exit 0 was rejected as suite evidence and is being fixed immediately as 578.
- Exact-SHA CI, green candidate gate and visible running-to-completed browser acceptance remain pending. The evidence above is not an observed candidate browser workflow. Norway benchmark B stays unchanged on rc.02.

2026-11-07 20:37 UTC: v2026.11.2-rc.03 is tagged at cb962d0a8be4aba086ffc7b44013e5875a633e9d with both Reports fixes. Corrected complete SQL fast suite passed all 129 tests at 20:26:59 UTC, real exit=0, including391 and390 (tmp/test-577-fast-combined-green.log and .exit). The first combined run's sole failure was321's 29 error-stack source offsets changing208->214 after the six-line start-notification addition. Apart from those offsets expected and observed output were byte-identical. Focused321 passed after the justified expected-context update cb962d0a8, then the complete suite passed. Exact candidate CI: Fast Tests42410876430, Harness42410614684, Go42410614674, App42410614676, Images42410614678 all completed/success. Candidate real install/upgrade/recovery gates are now running. Actual visible candidate browser running-to-completed acceptance remains pending after Norway B completes and the final green RC is installed. No claim that unit/native notification tests constitute observed browser acceptance.
<!-- SECTION:NOTES:END -->
