---
id: STATBUS-398
title: The install-failure banner explains that a later successful install or upgrade clears it
status: To Do
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-24 18:42'
labels:
  - install
  - upgrade
  - cli
  - ux
dependencies: []
priority: medium
type: task
ordinal: 88
---

## Description

Until the owner approves replacement wording, the banner says: “The last installation did not finish. Run the installer again. This message clears after a successful installation or upgrade.” Owner approval gates any wording change, not implementation of this provisional text.

## Evidence, 2026-09-24

Banner reading and writing is at `cli/cmd/support.go:169-170` at master `7a9cf707e`. Successful install clearing is at `cli/cmd/install.go:3042-3077`, and successful upgrade clearing is at `cli/internal/upgrade/service.go:4679-4683`, both at master `7a9cf707e`.

## Acceptance Criteria

- [ ] #1 `new: app/src/app/admin/upgrades/install-failure-banner-wording.test.ts` asserts the provisional sentence exactly until a cited owner decision replaces it.
- [ ] #2 `cli/internal/upgrade/install_failure_banner_test.go` proves a successful upgrade clears the banner.
- [ ] #3 `new: cli/cmd/install_failure_banner_test.go::TestSuccessfulInstallClearsBanner` proves a successful install clears the banner.
- [ ] #4 `app/src/app/admin/upgrades/install-failure-banner.test.ts` proves the UI shows the current persisted banner and hides it after clearing.
