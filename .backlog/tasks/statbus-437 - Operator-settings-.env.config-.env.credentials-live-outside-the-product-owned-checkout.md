---
id: STATBUS-437
title: Operator settings (.env.config, .env.credentials) live outside the product-owned checkout
status: To Do
assignee: []
created_date: '2026-10-01 11:39'
updated_date: '2026-10-01 12:05'
labels:
  - install
  - design
dependencies: []
priority: medium
ordinal: 385200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner question 2026-10-01, during the STATBUS-431 strategy discussion. Direction DECIDED by the owner 2026-10-01 12:04 UTC: **A-directory — `~/.statbus/`, same name everywhere, user-managed directory, no conflicts.**

### The layout

```
~/.statbus/                  mode 0700, owned by the install user, created by the operator or the installer
├── env.config               mode 0600 — deployment settings (today's ~/statbus/.env.config)
├── env.credentials          mode 0600 — secrets (today's ~/statbus/.env.credentials)
└── users.yml                mode 0600 — initial users (today's ~/statbus/.users.yml)
```

The generated artifact `~/statbus/.env` stays in the checkout: Docker Compose reads it from the project directory, and it is a product-owned render, not operator data. Only operator-authored sources move.

### Why this shape (discussion record)

- Operator-authored files live in the operator's own home, owned by the operator from birth; the product only reads them. No shared location where Docker (root) can win a creation race — the STATBUS-431 bug class.
- Hidden directory keeps `~` tidy; one entry, standard `~/.ssh` / `~/.aws` idiom; scales if more operator files appear.
- Rejected: flat dotfiles `~/.statbus.env` (three loose files, doesn't scale); `.env.statbus.x` (inverts the dependency — `.env` is the generated artifact, settings are the source; breaks format suffixes); visible `~/statbus.env.config` (consistent with `~/statbus-backups/` but secrets show in casual `ls`).
- Ordering dependency removed: cloud.sh/ops can place settings BEFORE the checkout exists (today ops/create-new-statbus-installation.sh must clone first, then touch .env.config).
- The checkout becomes purely product-owned: `rm -rf ~/statbus`, slot resets, and STATBUS-426's adopt scenario no longer lose identity or settings. Upgrade already uses `git checkout -f` (no `git clean`), so mid-upgrade swaps were safe even before.

### Migration

- Read order: `~/.statbus/env.config` first, legacy `~/statbus/.env.config` as fallback (same for credentials and users.yml).
- One-time move by the install user on the next install/upgrade pass; after the move the legacy file is absent. No symlinks.
- Provisioning (ops/create-new-statbus-installation.sh, cloud.sh, install.sh answer-file input, LXD harness) writes the new location only.
- All readers/writers updated in the same change: install step table (runCreateConfig, checkConfigDone, restoreSettingsBeforeDetect), config.Generate, cert install (updateEnvConfigCertPaths), upgrade service config regeneration, docs and remedy strings.

Explicitly deferred from the rc.02 scope (STATBUS-431).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Readers/writers inventory documented with exact references (install, upgrade service, cert install, cloud.sh, ops scripts, harness) and all updated in one change
- [ ] #2 Read order is new-location-first with legacy fallback; one-time move by the install user; verified on a guest upgrading from a release that still writes the legacy location
- [ ] #3 Wholesale checkout deletion (rm -rf ~/statbus) preserves identity and settings; STATBUS-426's adopt scenario passes against the new layout
- [ ] #4 Docs, remedies and AGENTS.md name the new location; no remaining reference tells an operator to edit files inside the checkout
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-01: direction decided by the owner after comparing A-files (`~/.statbus.env` flat dotfiles), B (`.env.statbus.x`), and C (visible `~/statbus.env.config`). A-directory chosen: same name, user-managed dir, no conflicts. Not rc.02 scope; schedule after the candidate gates.
<!-- SECTION:NOTES:END -->
