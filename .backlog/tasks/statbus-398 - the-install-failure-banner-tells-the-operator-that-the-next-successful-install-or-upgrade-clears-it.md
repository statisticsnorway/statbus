---
id: STATBUS-398
title: The install-failure banner explains that a later successful install or upgrade clears it
status: In Progress
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-25 10:28'
labels:
  - release-bug
  - install
  - upgrade
  - cli
  - ux
dependencies: []
priority: medium
type: task
ordinal: 88
---

## Status 2026-09-25

**Merged follow-up, proof pending.** `42be53b2e` (merge `7c9a2ead3`) supplies the provisional banner wording and `cli/cmd/install_failure_banner_test.go:9` (`TestSuccessfulInstallClearsBanner`), alongside the existing upgrade/UI tests described below. These are code/test observations, not an observed live banner transition through both successful install and upgrade. Remain In Progress until acceptance is proved by the gate.

**In Progress.** The provisional sentence now renders verbatim in the admin
banner and has an exact wording regression test (#1). The named installer
clearing test (#3) verifies that the successful-install path invokes the stamp
and its SQL clears all three persisted failure keys. Existing upgrade and UI
tests (#2, #4) passed. Observed: `go vet ./...`, `go test ./cmd
./internal/upgrade`, `gofmt -l cmd internal` (empty), and `golangci-lint run
./cmd/...` (0 issues); both banner Jest suites (3 tests), `pnpm run tsc`,
and Prettier check passed. No real installer/database or VM run was performed;
the new Go test checks source structure, not a live DB transition. Keep In
Progress pending an end-to-end install-clear observation if required for Done.

## Status 2026-09-24

**In Progress.** `8543f493a`: `cli/internal/upgrade/install_failure_banner_test.go` and `app/src/app/admin/upgrades/install-failure-banner.test.ts` cover successful-upgrade clearing and UI visibility (#2, #4); installer clearing is in `cli/cmd/install.go` but its named test (#3) is absent. The provisional exact wording test (#1) is absent. **Remaining:** assert owner-approved provisional sentence exactly and test clearing on successful install.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

Until the owner approves replacement wording, the banner says: “The last installation did not finish. Run the installer again. This message clears after a successful installation or upgrade.” Owner approval gates any wording change, not implementation of this provisional text.

## Evidence, 2026-09-24

Banner reading and writing is at `cli/cmd/support.go:169-170` at master `7a9cf707e`. Successful install clearing is at `cli/cmd/install.go:3042-3077`, and successful upgrade clearing is at `cli/internal/upgrade/service.go:4679-4683`, both at master `7a9cf707e`.

## Acceptance Criteria

- [ ] #1 `new: app/src/app/admin/upgrades/install-failure-banner-wording.test.ts` asserts the provisional sentence exactly until a cited owner decision replaces it.
- [ ] #2 `cli/internal/upgrade/install_failure_banner_test.go` proves a successful upgrade clears the banner.
- [ ] #3 `new: cli/cmd/install_failure_banner_test.go::TestSuccessfulInstallClearsBanner` proves a successful install clears the banner.
- [ ] #4 `app/src/app/admin/upgrades/install-failure-banner.test.ts` proves the UI shows the current persisted banner and hides it after clearing.
