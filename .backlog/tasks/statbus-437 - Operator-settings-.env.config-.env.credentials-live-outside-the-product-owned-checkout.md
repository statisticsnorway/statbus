---
id: STATBUS-437
title: >-
  Operator settings (.env.config, .env.credentials) live outside the
  product-owned checkout
status: To Do
assignee: []
created_date: '2026-10-01 11:39'
labels:
  - install
  - design
dependencies: []
priority: medium
ordinal: 385200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner question 2026-10-01, during the STATBUS-431 strategy discussion.

.env.config and .env.credentials are operator-owned data but live inside the product-owned git checkout (~/statbus/). Facts established in the discussion:
- Upgrade restores git state with `git checkout -f` only (no `git clean`), so untracked settings survive version swaps today.
- Wholesale checkout deletion paths destroy them: ops/reset-statbus-slot.sh wipes ~/statbus; STATBUS-426's adopt scenario is rm -rf ~/statbus + reinstall.
- ops/create-new-statbus-installation.sh must wait for the clone to exist before writing .env.config (ordering dependency).
- Operational state already lives outside the checkout: ~/statbus-backups, ~/statbus-maintenance.

Candidate direction: ~/statbus-config/ holding env.config, env.credentials and .users.yml, making the checkout purely product-owned and safe to delete at any time. Blast radius is mechanical but wide (config.ProjectDir assumptions, cert install, upgrade service, docs, harness). Explicitly deferred from the rc.02 scope (STATBUS-431).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Document the current readers/writers of ~/statbus/.env.config and .env.credentials (install, upgrade service, cert install, cloud.sh, ops scripts, harness) with exact references
- [ ] #2 Decide the operator-owned location and the one-time migration path (read new first, fall back to legacy, migrate on install/upgrade)
- [ ] #3 Migration preserves STATBUS-426's guarantees: wholesale checkout deletion no longer loses identity or settings
- [ ] #4 All docs, remedies and harness paths updated in the same change
<!-- AC:END -->
