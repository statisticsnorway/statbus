---
id: STATBUS-182
title: >-
  floor-oracle-ci-home: the empirical daemon-floor oracle runs standing in
  fast-tests; go-test lane gets a tested wiring invariant instead of the
  fail-loud
status: To Do
assignee: []
created_date: '2026-07-14 13:29'
labels:
  - ci
  - upgrade
  - testing
  - release-blocking
dependencies: []
priority: high
ordinal: 183000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a green master PROVES the daemon floor is sufficient — the empirical oracle (prepare all daemon queries at exactly-floor) runs in CI on every master push, forever, because the floor now lags the tree by design.
> FOUND: 2026-07-14 — Master Go Test RED since dc5c07339: TestDaemonFloorSchemaSufficient's designed fail-loud fired on the FIRST-EVER floor lag (DaemonSchemaFloor 20260712024457 < treeMax 20260714100527, the STATBUS-178 import-detector migration; CI has no cluster, STATBUS_FLOOR_TEST_DSN unset). No actual floor insufficiency exists — 178 touches only import.analyse/process_legal_relationship, zero DaemonRelationNames; the tripwire detected the LAG, as designed, and the resolution it demanded (build the oracle's CI home exactly when first needed) is this ticket.
> COMPLEXITY: mechanic or engineer, one commit (Go test edits + one workflow step + one new wiring test); architect ruling in comment #1 is the build spec. Blocks the release train (rc.06 does not cut on a red master).

Resolution ruled by the architect (comment #1): floor NOT bumped (option b rejected — scope rule); oracle homed in fast-tests.yaml (the lane that already provisions the full statbus DB); go-test lane's Fatal becomes skip-with-notice guarded by a NEW wiring-assert test so the cross-lane invariant is tested machinery, not trust.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 fast-tests.yaml provisions a database at EXACTLY DaemonSchemaFloor (template-clone at the migration waypoint preferred; second-baseline DB as fallback) and runs TestDaemonFloorSchemaSufficient with STATBUS_FLOOR_TEST_DSN — strict, failing the lane on any prepare failure
- [ ] #2 The oracle self-asserts non-vacuity: SELECT MAX(version) FROM db.migration must equal DaemonSchemaFloor or the test FAILS (replaces the do-not-point-at-HEAD comment with machinery)
- [ ] #3 go-test lane: the DSN-unset fail-loud becomes skip-with-notice (naming the CI home + local recipe), and a NEW TestFloorOracleWiredInCI in the pure lane asserts fast-tests.yaml carries the oracle invocation + floor-derivation — the wiring is a tested invariant
- [ ] #4 Master green restored at the landing commit; the oracle observed GREEN in fast-tests at that same sha (the first genuine empirical floor verdict)
- [ ] #5 DaemonSchemaFloor NOT bumped — 178 is outside the daemon SQL surface per the scope rule; the bump guard remains the only legitimate bump trigger
<!-- AC:END -->
