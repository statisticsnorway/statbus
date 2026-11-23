---
id: p9xte6
title: "The navbar shows the installation's country flag and name next to the logo"
state: todo
type: feature
priority: "low"
assignee: []
labels: []
group: ""
rank: "zzzzzzzzx"
created: 2026-11-23
updated: 2026-11-23
---

## Goal
Next to the StatBus logo, the navbar shows the configured country's flag as a Unicode emoji and the installation's name.

## Purpose
Owner 2026-11-23: with many country installations open in tabs (dev, demo, no, mz, ...), the header shows only the logo, so a user cannot see at a glance which country's register they are in.

## Principle
The flag comes from the configured country (settings.country_id, ISO alpha-2 turned into regional-indicator characters), the name from DEPLOYMENT_SLOT_NAME; no image files.

## Details
Navbar logo: app/src/components/navbar.tsx (Image statbus-logo.png, h-9 w-9). The app already has the name as PUBLIC_DEPLOYMENT_SLOT_NAME (layout.tsx, page title '<name> Statbus'). Windows renders flag emoji as two letters (MZ) rather than a flag; development slots with an invented code have no country flag.

## Depends on

## Acceptance
- [ ] [Owner] Approves the look (flag and name, or flag only; small text) from a screenshot on the test slot; recorded here
- [ ] On an installation configured for Mozambique, the navbar shows the Mozambique flag and the installation name next to the logo; a Playwright test asserts both
- [ ] With no country configured, the navbar shows the name only and no empty flag; a test asserts it

## Notes
