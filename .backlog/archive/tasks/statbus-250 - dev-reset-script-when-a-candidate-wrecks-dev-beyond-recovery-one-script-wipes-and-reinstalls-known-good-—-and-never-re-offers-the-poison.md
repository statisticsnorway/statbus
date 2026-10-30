---
id: STATBUS-250
title: >-
  dev-reset-script: when a candidate wrecks dev beyond recovery, one script
  wipes and reinstalls known-good — and never re-offers the poison
status: Done
assignee: []
created_date: '2026-08-19 09:09'
updated_date: '2026-08-19 11:58'
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
- [x] #1 One script wipes and reinstalls dev at the configured known-good target, using the existing installation tooling
- [x] #2 The wrecking candidate is marked dismissed on dev and is never auto-installed again; dev holds until a NEWER candidate exists
- [x] #3 The script is documented where the dev canary's role is documented, as the named answer to a wrecked canary
- [x] #4 The reinstall target is the previous STABLE release (King ruled 2026-08-19: "that is what people have — the previous release, and then they run the upgrade" — the reset recreates the customer's exact starting state, and dev's next auto-upgrade then walks the customer's exact path); INTERIM EDGE until the first stable exists in the current line: the previous release candidate is the fallback target
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

author: architect
created: 2026-08-19 11:44
---
BUILD DESIGN — execution-precise. One finding kills the obvious approach, and one gap must be filled before the script can work at all.

## THE OBVIOUS REUSE PATH DOES NOT WORK — verified, not assumed

The tempting design is to reuse the upgrade pipeline: register the previous stable, schedule it with `recreate=true`, and let the existing machinery back up, check out, recreate and restart. It reuses everything and touches no new code.

It cannot work. **`supersedeBelowInstalled` (service.go:4491) retires every `available` OR `scheduled` row whose newest tag is not newer than the installed version, and it runs on the discovery tick.** A reset is a DOWNGRADE by definition — its target is older than what is installed — so the scheduled row would be superseded out from under the reset on the next tick. Worse, it is a race: it would sometimes work, which is the most expensive kind of broken.

So the reset is a DIRECT script path. Do not route it through the upgrade ledger.

## THE GAP THAT MUST BE FILLED FIRST: there is no dismiss command

AC#2 requires the wrecking candidate be marked dismissed so it is never auto-installed again. **There is no `./sb upgrade dismiss`.** The subcommand set is check / register / list / schedule / apply-latest / channel / service / self-verify / self-rollback / trust-key. Today dismissal is an APP action — a PATCH from the admin UI (the write site the STATBUS-242 audit enumerates at `app/src/app/admin/upgrades/page.tsx`).

A script cannot dismiss through product tooling, and it must not write the row directly. **So this unit's first deliverable is `./sb upgrade dismiss <version>`** — small, obviously useful beyond this ticket (an operator who decides against a candidate has no CLI way to say so today), and it is what makes the rest of the script legitimate rather than surgery.

## THE SCRIPT — `ops/reset-statbus-slot.sh`

A NEW script, not a mode of `create-new-statbus-installation.sh`: that one verifies DNS, creates a Linux user, configures SSH access and picks a port offset — none of which a reset needs, and all of which would be dangerous to re-run against a live slot. Reuse the PRIMITIVES, not the entrypoint.

Steps, in order, each already existing:

1. **Refuse unless the slot is named explicitly** — no default target. This wipes a database; it must be impossible to run by accident on the wrong box.
2. **Determine the target**: previous STABLE via `git fetch --tags` then the newest `v*` tag without `-rc.`; if none exists in this line, the previous RC — the King's interim edge (AC#4). Same derivation as STATBUS-251's `TARGET_CHANNEL`; copy that pattern rather than inventing a second one. **Print the resolved target and refuse if it is empty.**
3. **Stop the upgrade service** (`systemctl --user stop statbus-upgrade@$USER`) BEFORE anything else — otherwise the daemon can discover, offer or act mid-reset.
4. **Stop services**: `./sb stop all`.
5. **Check out the target**: `git checkout <tag>` in the slot's checkout.
6. **Recreate the database and bring the box up at that version**: `./sb install`, which is the step-table — the same path an operator has for everything else.
7. **Dismiss the wrecking candidate**: `./sb upgrade dismiss <wrecking-version>` (the new command). The version is a required argument to the script — the human knows which candidate wrecked it; the script must not guess.
8. **Restart the upgrade service** and **verify from the RUNNING service**, not the file — the same lesson as the fleet correction: `journalctl --user -u 'statbus-upgrade@*'` must show the expected channel, and `./sb upgrade list` must show the wrecking candidate as dismissed and NOT offered.

## REWIND-SAFETY — already settled, and the answer is that nothing is owed

STATBUS-242's ruling applies directly: a restore rewinds to the snapshot of THAT upgrade, so any write made **before** an upgrade begins is inside the snapshot and survives. **The reset's dismissal happens outside any upgrade window** — it is a reset after a wreck — so it is in the snapshot of every subsequent upgrade and cannot be rewound by one. No special handling, no flag carriage. The hazard this ticket inherited is closed by that ruling rather than by code here.

## DOC PLACEMENT

Where the dev canary's role is documented — AGENTS.md's deployment section (the per-role model A2 rewrote), as the named answer to a wrecked canary, one line pointing at the script. Not a new document.
---

author: foreman
created: 2026-08-19 11:58
---
BOTH HALVES LANDED as 7e4c04124 (architect APPROVED as the pair). The reset script (ops/reset-statbus-slot.sh): explicit slot + wrecking-version required, optional [reset-target] escape hatch, GLOBAL previous-stable resolution (cross-line ruled correct — 'what people HAVE'; RC fallback only when no stable exists anywhere, noted as currently unreachable and untested), stop-service-first ordering, ./sb install as the reinstall path, dismissal via the new product command, verification from the RUNNING service. The companion `./sb upgrade dismiss`: pair write (state+dismissed_at), never-offered guaranteed by the existing state predicates and pinned against widening, three refusals that each say why, and the list rendering fixed under the generalized rule DECISION-STATES ABOVE HISTORY-STATES (both dismissed and skipped — the sibling latent bug fixed in the same pass per never-defer-known-bugs), with the cross-mechanism tripwire noted at the CASE naming both re-arm NULLing sites. All four ACs closed. The script's first real exercise awaits an actual wrecked canary — may it be a long wait.
---
<!-- COMMENTS:END -->
