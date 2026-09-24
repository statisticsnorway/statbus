---
id: STATBUS-413
title: A push that changes only generated doc/db/ files rides the parent's green runs
status: In Progress
assignee: []
created_date: '2026-09-24 23:55'
updated_date: '2026-09-24 23:55'
labels:
  - release-bug
  - ci
  - release
dependencies: []
priority: medium
type: bug
ordinal: 364000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A commit that changes only generated database-reference Markdown under `doc/db/` inherits the applicable green content verdicts from its first-parent commit, rather than paying to repeat unchanged Go and application checks. Images still publishes verifiable artifacts at the new SHA by the existing parent-retag path. No hand-authored documentation, migration, test, code, or mixed commit is exempt by accident.

## Grounded evidence, 2026-09-24

- `10f094f2b` changed only `doc/db/table/public_upgrade.md` and `doc/db/view/public_statistical_unit_def.md` (`git show --stat 10f094f2b`). Nevertheless Go Test run [36062511490](https://github.com/statisticsnorway/statbus/actions/runs/36062511490), app build & lint [36062511473](https://github.com/statisticsnorway/statbus/actions/runs/36062511473), and Images [36062511465](https://github.com/statisticsnorway/statbus/actions/runs/36062511465) all completed successfully at that SHA after running. The run IDs establish redundant work, not by themselves a safe exemption.
- `ops/release/ci-exempt-paths.txt:1-27,41-63` currently exempts only `.backlog/`, explicitly says `doc/` is not included and lists the synchronized Go/app trigger filters. `cli/cmd/release/release.go:1567-1656,178-205` implements anchored first-parent verdict riding, and `cli/cmd/release/release_ci_exempt_ride_test.go:25-113` covers fail-closed matching.
- `.github/workflows/go-test.yaml:41-45` and `.github/workflows/app_build_and_lint-workflow.yaml:16-22` ignore `.backlog/**` on pushes, not `doc/db/**`. `.github/workflows/images.yaml:86-220,342-389` decides exempt-only changes and verifies retagged parent images. On `.backlog/`-only commit `8b73ca1fb`, Images run [36031394505](https://github.com/statisticsnorway/statbus/actions/runs/36031394505) recorded five successful parent-retag jobs with the build skipped. The seed job has separate semantics (`images.yaml:391-446`) and must retain its publication contract.
- Work is active on worker blowfish's `ci/docdb-exempt` branch, not merged at the baseline `373d15fc3`. **In Progress describes that active implementation, not accepted master behavior.**
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A repository test establishes that only generated `doc/db/` paths join `.backlog/` in `ops/release/ci-exempt-paths.txt` and in the Go/app push filters; `doc/` generally, source inputs, migrations, `test/`, mixed commits, and the policy file itself require fresh checks.
- [ ] #2 The release gate reports the parent SHA, exact green run IDs and changed-file count when a generated-doc-only commit rides green Go/app/Fast Tests verdicts; a red or pending parent cannot be ridden, and Images still requires an artifact at the new SHA.
- [ ] #3 The Images workflow chooses its existing verified parent-retag path for a `doc/db/`-only push and publishes publicly verifiable service image tags at the tip, while preserving the seed-image publication invariant. A missing parent artifact fails toward full build.
- [ ] #4 A pushed `doc/db/`-only commit is observed in Actions: Go/app omit redundant runs, Images uses retag rather than full service builds, and release preflight accepts the parent's recorded green content verdicts without confusing a missing tip run with a new green run. Record the run IDs and the exact parent/tip SHAs.
<!-- AC:END -->
