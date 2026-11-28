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
stage: "waiting"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
waiting_asked_by: "hibiscus"
waiting_on: "owner's placement feedback (flag and name below the version line) is next after the Reports Map in today's walkthrough"
waiting_since: "2026-11-27T17:04"
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
- [x] With no country configured, the footer shows the name only and no empty flag; a test asserts it

## Questions
- 2026-11-27T15:09 question 1 by hibiscus to jhf:
  The footer now starts with the country flag and the installation name, small and grey like the version text: screenshot at statbus_test tmp/p9xte6-footer-norway.png (🇳🇴 local, then GitHub, website, version). On master as c9647bde1. Approve the look, or what should change?
  answered 2026-11-27T15:37 by jhf:
    There is no file attached to this image. I have to look at that in conjunction with you. Referencing temp file is not valid, so I'm gonna disregard that

## Notes


check 2: c9647bde1: footer.test renders an installation in Mozambique with flag 🇲🇿 (aria-label Mozambique) and its name (red on the old footer, green now; tmp/p9-footer-red.log, -green.log). Headless on the test slot with settings.country_id set to MZ: footer shows 🇲🇿 local (tmp/p9xte6-footer-mozambique.log/.png); country restored to Norway.
check 3: c9647bde1: footer.test 'with no country the footer shows the name only, with no empty flag': no role=img, text is the name only. (settings.country_id is NOT NULL, so this also covers an invented two-letter-less code via flagEmoji's null.)
landed c9647bd on master 2026-11-27: app: the footer shows the installation's country flag and name (p9xte6)
2026-11-27 14:29 (hibiscus) CI on c9647bde1 (master) all success: Images, app build & lint, Go Test, Harness Selftest, Fast Tests. Waiting on check 1, the owner's verdict on the look (question asked).
2026-11-27 14:38 (hibiscus) Owner: a tmp file is not a valid way to show the look; we look at it together in Firefox. Done at item 3 of today's walkthrough, in tab 145 (the footer is at the bottom of every page).
2026-11-27 14:43 (owner, in Firefox) Placement: flag and name should sit below the 'Statbus version' line, both adjusted to match. Alternatives he named: left of the header logo (but that reads as a language selector, which it is not), or the flag as a small subscript on the logo rather than beside it. Next: show the below-version and logo-subscript variants in Firefox.
shipped in v2026.11.7 (c9647bd)
## History
- 2026-11-27T15:05 todo -> doing/active (take with j2g6wd)
- 2026-11-27T15:09 doing/active -> doing/asked (ask)
- 2026-11-27T15:37 answered asked, by jhf, for hibiscus (doing/asked -> doing/active):
  > The footer now starts with the country flag and the installation name, small and grey like the version text: screenshot at statbus_test tmp/p9xte6-footer-norway.png (🇳🇴 local, then GitHub, website, version). On master as c9647bde1. Approve the look, or what should change?
  There is no file attached to this image. I have to look at that in conjunction with you. Referencing temp file is not valid, so I'm gonna disregard that
- 2026-11-27T15:37 answer 1 delivered to hibiscus (session_hibiscus_1793348926173_ffff8733f4ad20e1)
- 2026-11-27T15:38 answer 1 acknowledged by hibiscus
- 2026-11-27T17:04 doing/active -> doing/waiting (wait)
- 2026-11-27T17:04 hibiscus read the answer: hug task wait p9xte6 "owner's placement feedback (flag and name below the version line) is next after the Reports Map in today's walkthrough"
- 2026-11-27T17:04 outcome 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-27T17:04 outcome 1 acknowledged by rabbit
