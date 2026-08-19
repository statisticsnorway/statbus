---
id: STATBUS-250
title: >-
  dev-reset-script: when a candidate wrecks dev beyond recovery, one script
  wipes and reinstalls known-good — and never re-offers the poison
status: To Do
assignee: []
created_date: '2026-08-19 09:09'
labels:
  - ops
  - release
dependencies: []
references:
  - ops/create-new-statbus-installation.sh
  - doc/CLOUD.md
priority: medium
type: enhancement
ordinal: 243000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
dev is the automatic canary: it takes every release candidate first, and the recovery machinery (rollback, park, un-park) is expected to repair it when a candidate hurts it. But a canary can, rarely, be wrecked beyond what recovery handles — and the King's ruling (2026-08-19, alongside the STATBUS-246 approval) is that this case gets one programmatic answer, not an improvised afternoon: "this release candidate fed up dev — wipe and reinstall."

WHAT THE SCRIPT DOES: wipe the dev slot and reinstall it at a known-good version, using the existing installation tooling (ops/create-new-statbus-installation.sh is the starting point). One command, no archaeology.

THE SUBTLETY THAT MAKES IT MORE THAN A REINSTALL: dev follows the candidate channel. A reset that leaves the wrecking candidate as "latest" would auto-upgrade straight back into the poison on the next tick. So the reset must also mark that candidate dismissed/skipped ON DEV, and dev then holds at the known-good version until a NEWER candidate appears.

OPEN KING DECISION (deliberately unforced — he said "not sure yet"): the reinstall target. (a) The previous release CANDIDATE — keeps dev maximally close to the bleeding edge; (b) the previous STABLE release — the most-proven floor, with dev re-upgrading to the next candidate within a tick anyway (the foreman's lean, offered as input: a wipe means recovery already lost at RC level, so restart from the most-proven ground; nothing is lost but the poison). The entry carries both until he rules.

WHAT IS ACHIEVED: the worst case on the automatic canary has a bounded, scripted cost — "dev is hard to restart" stops being an argument in any future design discussion, because restarting dev is one command.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One script wipes and reinstalls dev at the configured known-good target, using the existing installation tooling
- [ ] #2 The wrecking candidate is marked dismissed on dev and is never auto-installed again; dev holds until a NEWER candidate exists
- [ ] #3 King decides the reinstall target (previous RC vs previous stable) before implementation
- [ ] #4 The script is documented where the dev canary's role is documented, as the named answer to a wrecked canary
<!-- AC:END -->
