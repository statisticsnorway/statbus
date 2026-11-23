---
id: p9xte6
title: "The footer shows the installation's country flag and name"
state: todo
type: feature
priority: "low"
assignee: []
labels: []
group: ""
rank: "00000000000g"
created: 2026-11-23
updated: 2026-11-23
---

## Goal
The footer, beside the GitHub and website icons and the version, shows the configured country's flag emoji and the installation's name.

## Purpose
Owner 2026-11-23: with many country installations open in tabs (dev, demo, no, mz, ...), the header shows only the logo, so a user cannot see at a glance which country's register they are in.

## Principle
The flag comes from the configured country (settings.country_id, ISO alpha-2 turned into regional-indicator characters), the name from PUBLIC_DEPLOYMENT_SLOT_NAME; no image files.

## Details
Owner 2026-11-23: in the footer, more subtle than the navbar. Footer: app/src/components/footer.tsx (Github and Globe icons, 'Statbus version vX (sha)'). The app already has the name as PUBLIC_DEPLOYMENT_SLOT_NAME (layout.tsx, page title '<name> Statbus'). Windows renders flag emoji as two letters (MZ) rather than a flag; development slots with an invented code have no country flag.

## Depends on

## Acceptance
- [ ] [Owner] Approves the look (flag and name, size and placement) from a screenshot on the test slot; recorded here
- [ ] On an installation configured for Mozambique, the footer shows the Mozambique flag and the installation name; a Playwright test asserts both
- [ ] With no country configured, the footer shows the name only and no empty flag; a test asserts it

## Notes
