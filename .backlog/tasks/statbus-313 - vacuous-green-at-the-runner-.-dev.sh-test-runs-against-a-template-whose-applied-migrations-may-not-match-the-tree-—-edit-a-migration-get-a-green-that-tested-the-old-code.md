---
id: STATBUS-313
title: >-
  vacuous-green-at-the-runner: ./dev.sh test runs against a template whose
  applied migrations may not match the tree — edit a migration, get a green that
  tested the old code
status: To Do
assignee:
  - engineer
created_date: '2026-08-28 23:13'
labels:
  - testing
  - tooling
dependencies: []
priority: high
type: bug
ordinal: 306000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a green test must mean the code in the tree passed. Tonight it did not: `./dev.sh test 098` returned green against a trigger definition that had already been edited on disk — the template carried the pre-edit migration, so the run exercised code that no longer exists. The engineer predicted the vacuity before running, ran anyway to establish the fact, and refused to bless the result. That refusal is the only reason this class was caught.

THE GAP, precisely: the stale-stamp guard (content_hash of applied migrations vs on-disk files) already fires loudly for `create-test-template` and `./sb types generate` — both refused earlier the same evening. `./dev.sh test` performs NO such check: it clones the template and runs, silently, whatever migration state the template happens to carry. Edit any migration, run its test, get a green that verified the previous bytes. No warning, no refusal.

WHY IT MATTERS BEYOND TONIGHT: this is the vacuous-green class living in the runner itself — the exact instrument we use to prove changes. It is also the same shape as the STATBUS-312 divergences (a template built from one migration state while the tree holds another), so closing it removes a standing source of false confidence for every future migration edit.

THE FIX (the engineer's framing, adopted): the test runner refuses — or at minimum warns loudly — when the template's applied migration hashes disagree with the on-disk migration files, exactly the check its sibling commands already enforce. Refuse-with-named-fix preferred per house norm (the message names the rebuild command), loud-warn acceptable only if a refusal would block legitimate flows we identify during implementation.

STAFFING: engineer (he found it, he owns dev.sh's isolation machinery from STATBUS-274), AFTER the 309 final freeze.

WHAT IS ACHIEVED: a green from ./dev.sh test once again proves the tree's code, and the edit-a-migration-and-trust-the-old-green pathway is closed at the instrument.
<!-- SECTION:DESCRIPTION:END -->
