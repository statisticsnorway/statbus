---
id: STATBUS-355
title: >-
  promotion renames the running version everywhere: one resolver from commit to current name; provenance labeled, never contradictory
status: In Progress
assignee: []
created_date: '2026-09-04 11:07'
updated_date: '2026-09-04 20:20'
labels:
  - upgrade
  - app
  - ux
dependencies: []
priority: high
type: bug
ordinal: 348000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Observed defect

Dev installed `v2026.09.0-rc.14` at commit `d53731ec5`. The same commit was then
promoted to `v2026.09.0`. Discovery correctly enriched the completed ledger row
with both tags and promoted its release status, so the card title resolved to
the stable name. The footer and provenance line still displayed the install-
time RC name. Demo, installed after promotion from the same image, displayed
stable everywhere. The contradiction was read-time identity drift, not a new
upgrade.

## Identity rule

The running identity is the installed commit resolved through
`public.display_name(upgrade)`: stable tag first, then prerelease tag, then
short SHA. Artifact and event-time names remain immutable provenance and appear
only with labels such as `built as` or `installed as`. `./sb --version` remains
exactly the build label.

## Completed

- Migration `20260904111126` publishes the installed commit, its resolved
  running name, release status, and build provenance through the database API,
  using the same resolver as the upgrade card.
- The footer resolves the running commit through that API and falls back to the
  injected build name plus commit short when the resolver is unavailable.
- The admin card no longer presents the install-time name as an unlabeled
  competing current version.
- `./sb upgrade list` displays resolved running identity and keeps build/install
  names explicitly labeled as provenance.
- The same-commit upgrade skip, lifecycle rows, timestamps, callbacks,
  `./sb --version`, and stored provenance semantics were left unchanged.
- `DaemonSchemaFloor` was raised to `20260904111126` so an old daemon cannot
  operate against the new identity contract.

## Observed validation

Go suites, app TypeScript, `331_running_identity`, and the RLS/grant checks all
passed. The database test covers an installed RC commit gaining a same-SHA
stable tag and verifies the resolved identity changes without inserting or
scheduling an upgrade.

## Remaining

Close this ticket only after one real batch RC is promoted to a stable tag at
the same SHA and the already-running dev installation changes every current-
identity surface to the stable name without reinstalling or recreating the app
container. Verify the RC name remains visible only as labeled provenance and
`./sb --version` remains the RC build label.
<!-- SECTION:DESCRIPTION:END -->
