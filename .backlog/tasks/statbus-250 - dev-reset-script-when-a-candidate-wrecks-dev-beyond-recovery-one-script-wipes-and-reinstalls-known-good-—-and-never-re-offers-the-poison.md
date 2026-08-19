---
id: STATBUS-250
title: >-
  dev-reset-script: when a candidate wrecks dev beyond recovery, one script
  wipes and reinstalls known-good — and never re-offers the poison
status: To Do
assignee: []
created_date: '2026-08-19 09:09'
updated_date: '2026-08-19 10:35'
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
- [ ] #3 The script is documented where the dev canary's role is documented, as the named answer to a wrecked canary
- [ ] #4 The reinstall target is the previous STABLE release (King ruled 2026-08-19: "that is what people have — the previous release, and then they run the upgrade" — the reset recreates the customer's exact starting state, and dev's next auto-upgrade then walks the customer's exact path); INTERIM EDGE until the first stable exists in the current line: the previous release candidate is the fallback target
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-19 09:28
---
OPEN DECISION CLOSED by the King 2026-08-19: reinstall target = previous STABLE release. His reasoning, near verbatim: "we should restore the previous release because that is what people have — they have the previous release and then they run the upgrade; that is the sensible baseline." Foreman offered no pushback — the ruling is the fidelity argument itself: the reset recreates the customer's starting state, and the subsequent auto-upgrade to the next candidate exercises exactly the stable→next path customers will take. Edge added to AC: until the first stable exists in this line (true today), previous RC is the interim fallback.
---

author: foreman
created: 2026-08-19 10:15
---
HAZARD INHERITED FROM THE 242 ENUMERATION (architect, Finding 1): the rollback's database restore rewinds ALL of public.upgrade, not just the upgrading row — and dismissed_at is one of the columns nothing re-derives. Concretely for this entry: the reset marks the wrecking candidate `dismissed` so it is never re-offered; if a LATER upgrade on the same box rolls back, the restore can rewind that dismissal and the wrecking candidate comes back as `available` — the operator's deliberate act silently undone, and this ticket's core guarantee broken by machinery it never sees. The builder must either verify 242's mechanism (which forces disposition of dismissed_at/skipped_at/superseded_at at the terminal write) lands first, or make the reset's dismissal robust against the rewind by its own means — not assume the column survives.
---

author: architect (pinned by foreman)
created: 2026-08-19 10:35
---
HAZARD FROM COMMENT #2 CLEARED (242 review ruling, the insight everyone missed including its filer): a rollback restore rewinds to the snapshot OF THAT UPGRADE, so any write made BEFORE the upgrade started is inside the snapshot and survives. The dev-reset's dismissal happens outside any upgrade window — it is a reset after a wreck — so it sits in the snapshot of every subsequent upgrade and SURVIVES their rollbacks. The builder does NOT need to make the dismissal rewind-robust. Residual (recorded, not engineered away): a dismissal made while an upgrade is in flight is lost on that rollback — human-visible (the row reappears) and one click to redo.
---
<!-- COMMENTS:END -->
