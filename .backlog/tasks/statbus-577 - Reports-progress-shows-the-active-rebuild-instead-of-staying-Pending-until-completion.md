---
id: STATBUS-577
title: >-
  Reports progress shows the active rebuild instead of staying Pending until
  completion
status: Done
assignee: []
created_date: '2026-11-07T19:56:00Z'
updated_date: '2026-11-08T09:00:00Z'
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
- [x] #2 The navbar displays the actual active reports step and its available progress, while correctly distinguishing waiting for unit derivation from running reports.
- [x] #3 Relevant SQL/frontend tests and exact-SHA CI pass; the candidate browser workflow visibly transitions through running reports to completion.
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

2026-11-07 23:41 UTC: Both rc03 and final rc04 (929fe787c2ab323d3a8c6d013bb9864fbec7bd67) completed their full release gates. RC04 Orchestrator42421987884 and Upgrade Arc Harness42422939393 explicitly completed/success, alongside Release/Smoke/Hardening/Fast/LXD/dev canary. Norway B is complete and documented without repeating it. On installed rc03, authorized real recalculation50063 began21:48:38; the authenticated Reports waiting popover was visibly captured21:51:44 in tmp/rune-measure/final-rc03/reports-waiting-browser.png. Read-only server observations then recorded active Reports at22:08:37.966639, reducer progress at22:09:29/45, and complete idle22:10:00.407563 with zero failed tasks. Those server transitions are not browser acceptance: the Mac locked before running/idle screenshots, Chrome AX reported no accessible windows and per-window capture failed. The missing real running/idle visual check remains explicit, AC2/3 unchecked and ticket In Progress. No unlocking, security-setting change or SQL-only substitution. Final named rc04 is now registered/scheduled through the supported Norway upgrader after full gate success, with unchanged stocks/history and idle clean-host baseline captured23:33.

2026-11-08 09:00 UTC final installed-candidate browser acceptance PASS:
- Norway is serving v2026.11.2-rc.04, exact artifact 929fe787c2ab323d3a8c6d013bb9864fbec7bd67. Full RC04 gates remain completed/success: Orchestrator42421987884, LXD42422880347, Upgrade Arc Harness42422939393, Smoke42422098754, Hardening42421987943, tag Fast42421988059, release42421987857 and dev canary42422765530. Exact source and prior closure CI are green.
- Supported, idle-guarded full recalculation53750 started08:36:26UTC on November8. The authenticated Firefox Norway tab displayed waiting during unit derivation. Its actual DOM then recorded Computing search facets / Running at08:56:06, available69% at08:56:26, Merging search facets at08:56:27, Merging history changes at08:56:49, and final idle with progress-details control removed08:57:31. Navbar fill advanced0% ->69% ->76% before idle.
- Coordinator directly inspected real Firefox screenshots: waiting, Computing search facets / Running08:56:16, Merging history changes / Running08:57:10, and final idle08:59:34. The persistent initial waiting screenshot is tmp/rune-measure/reports-rc04-20261108/waiting-browser.png. Browser bridge screenshots were returned and visually inspected in the session, not claimed to be persistent native files. Actual page DOM records exported to browser-transitions.json. Transient null-dialog records are not counted as running evidence.
- The original native per-window observer failed honestly when the desktop locked08:49 (observe.exit=1, preserved). The normal Firefox bridge continued to work without unlocking or security-setting changes. The resumed read-only correlator finished with actual observe-bridge.exit=0; no duplicate recalculation was queued.
- Positive final verifier tmp/rune-measure/reports-rc04-20261108/verify-acceptance.mjs PASS09:00:20: actual browser waiting -> labeled running -> idle, pipeline53750 completed, zero failed tasks across samples, exact healthy rc04 artifact, SQL writes enabled, both worker states idle, all four unit stocks and eight history summary rows equal the pre-recalculation baseline. after-state.out, monitor.json, build.json, status.jsonl and verified-acceptance.json preserve the evidence.
- This closes the former real-browser gap. Prior SQL391 RED/GREEN, committed native notifications, complete129SQLsuite,208frontendtests/tsc/lint/build and exact-source CI remain documented above. No additional product code or migration changed during this acceptance, benchmarkB was not repeated, and591 remains excluded.
<!-- SECTION:NOTES:END -->
