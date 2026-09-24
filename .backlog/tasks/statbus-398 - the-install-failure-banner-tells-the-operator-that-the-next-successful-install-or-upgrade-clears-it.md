---
id: STATBUS-398
title: >-
  The install-failure banner tells the operator that the next successful install
  or upgrade clears it
status: To Do
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-24 14:53'
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

The install-failure banner tells the operator that the next successful install
or upgrade clears it.

## Done when

- The banner shows the agreed wording.
- After a later successful install or upgrade, the banner is gone.

## 2026-09-24 status

The wording decision is **OPEN with the owner**. Next step: confirm the exact
phrase, update the banner and its tests, and verify the message disappears
after a later successful install or upgrade.

## Review correction 2026-09-24

Until owner confirmation, use the provisional phrase: “The last installation did not finish. Run the installer again; this message clears after a successful installation or upgrade.” Banner reading/writing is anchored at `cli/cmd/support.go:169-170`. Clearing is already implemented for successful install and upgrade (`cli/cmd/install.go:3042-3077`; `cli/internal/upgrade/service.go:4679-4683`). Add a named new UI/banner wording test and cite the existing successful install/upgrade clearing tests.
