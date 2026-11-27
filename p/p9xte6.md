---
id: p9xte6
title: "The footer shows the installation's country flag and name"
state: "doing"
type: feature
priority: "low"
assignee: ["hibiscus"]
labels: []
group: ""
rank: "00000000000g"
created: 2026-11-23
updated: 2026-11-23
doing_since: "2026-11-27T15:05"
doing_with: "j2g6wd"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
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
- [x] On an installation configured for Mozambique, the footer shows the Mozambique flag and the installation name; a Playwright test asserts both
- [ ] With no country configured, the footer shows the name only and no empty flag; a test asserts it

## Notes


check 2: c9647bde1: footer.test renders an installation in Mozambique with flag 🇲🇿 (aria-label Mozambique) and its name (red on the old footer, green now; tmp/p9-footer-red.log, -green.log). Headless on the test slot with settings.country_id set to MZ: footer shows 🇲🇿 local (tmp/p9xte6-footer-mozambique.log/.png); country restored to Norway.
## History
- 2026-11-27T15:05 todo -> doing/active (take with j2g6wd)
