---
id: STATBUS-182
title: >-
  floor-oracle-ci-home: the empirical daemon-floor oracle runs standing in
  fast-tests; go-test lane gets a tested wiring invariant instead of the
  fail-loud
status: To Do
assignee: []
created_date: '2026-07-14 13:29'
updated_date: '2026-07-14 13:37'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-14 13:37
---
RULING + BUILD SPEC (architect, 2026-07-14) — the re-ruling the test header defers ("awaiting the architect's re-ruling on comment #4", daemon_floor_empirical_test.go:64-65), now due on the tripwire's first firing.

ADJUDICATION OF THE THREE OPTIONS:
(b) FLOOR BUMP — REJECTED, the foreman's reading is correct and verified: migration 20260714100527 contains exactly two CREATE OR REPLACE PROCEDURE statements, import.analyse_legal_relationship (:23) and import.process_legal_relationship (:376) — none of the DaemonRelationNames. The floor's own scope rule (daemon_floor.go:38-45: the floor set is the daemon binary's SQL surface) forbids the bump; bumping would widen the UNGUARDED boot-time migration window (the whole point of 145 was bounding it) and teach the bump-to-green reflex. The floor lagging the tree is the system's NORMAL state from now on — which is why the oracle needs a standing home, not a one-off fix.
(c) ARM-ONLY-ON-DAEMON-TOUCH — REJECTED: reintroduces exactly the blind spot the empirical oracle exists to cover (an unqualified daemon-relation reference the static bump guard cannot see, test header :69-70).
(a) CI RUNS THE ORACLE — ACCEPTED, with one correction to the proposed placement: NOT go-test.yaml. The oracle needs the statbus DB image (custom extensions; a vanilla postgres service cannot run our migrations — the refuted self-provisioning note :56-65 already proved from-scratch migrate.Up fails without the create-db baseline). Putting it in go-test.yaml would make the pure-Go lane Docker- and Images-dependent — the exact coupling that lane's header explicitly rejects — and would duplicate fast-tests' provisioning. The oracle is not a pure Go test; it lives where its essential dependency already exists: fast-tests.yaml (self-contained runner, checkout → build sb → compose up → create-db).

BUILD SPEC — one commit, three pieces (mechanic or engineer, foreman's dispatch call):
1. fast-tests.yaml gains a floor-oracle step. Preferred provisioning: WAYPOINT CLONE — run the create-db baseline, `./sb migrate up --to <floor>`, `CREATE DATABASE statbus_floor TEMPLATE <db>`, then continue migrating the main DB to HEAD as today; pg_regress flow otherwise untouched (the clone-template genre is the suite's existing machinery). Fallback if create-db cannot split baseline-from-migrate: provision a second DB from the baseline and migrate it --to floor. Then `STATBUS_FLOOR_TEST_DSN=postgres://…/statbus_floor go test ./internal/migrate/ -run TestDaemonFloorSchemaSufficient` — STRICT, no continue-on-error. The floor value is DERIVED from the single source of truth (grep `DaemonSchemaFloor = ` in cli/internal/migrate/daemon_floor.go), never hardcoded in the workflow.
2. The oracle self-asserts NON-VACUITY (new, in the Go test): after connect, `SELECT COALESCE(MAX(version),0) FROM db.migration` must EQUAL DaemonSchemaFloor, else FAIL naming the actual value — machinery replaces the do-not-point-at-HEAD comment. This is what makes the CI step trustworthy: a mis-provisioned (HEAD) DB can never pass vacuously again.
3. go-test lane: the DSN-unset+floor-lags branch (daemon_floor_empirical_test.go:93-100) changes Fatal → Skip-with-notice naming the CI home (fast-tests floor-oracle step) + the local recipe. The teeth move into a NEW pure-lane test, TestFloorOracleWiredInCI: reads .github/workflows/fast-tests.yaml from the repo and asserts (i) the `-run TestDaemonFloorSchemaSufficient` invocation with STATBUS_FLOOR_TEST_DSN is present and (ii) the floor-derivation grep pattern it relies on actually matches daemon_floor.go — the cross-lane invariant becomes TESTED MACHINERY, not trust (same source-shape-assert genre as persistent_rsync_test). Deleting the workflow step turns the pure lane red again by construction.

WHY Fatal→Skip IS NOT A WEAKENING: today the oracle runs NOWHERE in CI — the Fatal only detects the lag, it cannot detect an insufficiency. After this commit the oracle genuinely RUNS on every master push (strictly stronger), the wiring is asserted in the pure lane on every push and PR, and green master ⇒ the daemon queries prepared clean at exactly-floor. Local `go test ./...` without a cluster skips with the recipe instead of failing forever — the duty-holder for the empirical verdict is CI, not every laptop.

SEQUENCING (today's red): all three pieces land in ONE commit → go-test lane green immediately (skip + wiring test passes against the same-commit workflow); fast-tests at that sha delivers the first genuine empirical floor verdict (expected GREEN — 178's migration is above the floor and not applied to the floor DB; the daemon surface is untouched). Master green → the release train (rc.06) unblocks. Images-failed masters skip fast-tests, which is acceptable: such a master is already red on the Images gate and nothing releases from it.

Out of scope, unchanged: the static bump guard, DaemonRelationNames, the completeness sweep test, the floor value itself.
---
<!-- COMMENTS:END -->
