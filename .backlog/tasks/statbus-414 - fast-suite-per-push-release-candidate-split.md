---
id: STATBUS-414
title: The fast suite holds the checks every push needs, and longer scenarios run for release candidates
status: To Do
assignee: []
created_date: '2026-09-24 23:55'
updated_date: '2026-09-24 23:55'
labels:
  - owner-decision
  - ci
dependencies: []
priority: medium
type: task
ordinal: 365000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The per-push Fast Tests lane gives a timely, meaningful regression verdict. Tests that do not need to run on every push remain release-candidate gates rather than disappearing. An owner-approved, measured test-by-test division keeps the candidate's total assurance intact and reduces feedback latency without declaring expensive tests unimportant.

## Grounded evidence, 2026-09-24

- GitHub Actions Fast Tests run [36051439861](https://github.com/statisticsnorway/statbus/actions/runs/36051439861) started 19:55:45Z and ended 20:09:46Z (14m01s, success); [36048233095](https://github.com/statisticsnorway/statbus/actions/runs/36048233095) ran 19:27:07Z–19:39:55Z (12m48s, failure); [36043751175](https://github.com/statisticsnorway/statbus/actions/runs/36043751175) ran 18:48:02Z–19:03:45Z (15m43s, failure). These are whole-workflow elapsed times including setup. Their three-sample median is **14m01s**, not an independently measured per-test median. Failure is an outcome, not a reason to discard the timing sample.
- A local `./dev.sh migrate-and-test fast` took approximately 9.2 minutes in the reported development environment. A per-test profile is being collected in `tmp/fast-test-timing.md` outside the tracked tree; that profile has not yet been accepted as a fixture or an owner-approved cut list. The local and CI totals use different environments and must not be treated as comparable test-only runtimes.
- `.github/workflows/fast-tests.yaml:35-66` runs the fast suite after Images on the runner and distinguishes it from the full external pg_regress lane. `cli/cmd/release/release.go:141-253,264-360` checks a fast-suite local stamp or CI verdict, with migration-version and `test/expected/` drift checks. `.github/workflows/fast-tests.yaml:56-61` states stable promotion requires green Fast Tests at the candidate SHA. A changed test selection must preserve both stable and prerelease coverage rules.
- **Owner decision required:** identify which specific tests remain per push, which move to a release-candidate proof, and what measured feedback target is worthwhile. No test is moved merely because it is slow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A reproducible per-test timing inventory records exact test name, runtime, setup versus execution cost, runner/local environment, source commit, and at least one representative full fast-suite baseline. The owner approves a named per-push versus release-candidate matrix based on risk and time, not a blanket duration cutoff.
- [ ] #2 Each moved test runs on the release-candidate path against the candidate commit and its outcome is a required, SHA-attributed green verdict before stable promotion. A deliberately failing moved test blocks the candidate, and no test is silently omitted from both tiers.
- [ ] #3 The per-push Fast Tests lane still checks every owner-designated high-signal path and remains a required green gate where the current release contract requires it. `cli/cmd/release/release.go` stamp, migration and expected-file drift checks continue to reject stale coverage; prerelease and stable checks are exercised separately.
- [ ] #4 Before/after Actions runs at comparable commits and environments record the new per-push wall time, candidate-tier wall time and test counts, with failed as well as successful outcomes retained. The owner confirms the latency/assurance tradeoff against the accepted matrix.
<!-- AC:END -->
