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
updated_date: '2026-08-28 23:24'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-28 23:24
---
**Built — frozen unstaged, awaiting review.** `./dev.sh test` now asks the content-hash question its siblings already ask. One line of wiring, no new machinery.

**The fix.** `dev.sh` line ~1549, immediately after the existing `assert-db-at-head` block in the `'test' )` arm (line 1248):

    ./sb assert-db-content-hash "$SEED_NAME_PRECHECK" "./dev.sh test" || exit 1

The command already exists and is landed — `cli/cmd/assert_db_content_hash.go`, added by STATBUS-292 at `dec0b4baf`. **`generate-doc-db` already makes exactly this pairing** (`dev.sh:2830` + `dev.sh:2844`), with a comment saying `assert-db-at-head` is blind to "same version, amended bytes". The test runner was the remaining sibling asking only half the question — which is why it was the one that got caught. So this is reuse, not new code: nothing to duplicate, and one implementation of the diagnostic contract.

**Scope, verified not assumed.** The gate sits in the `'test' )` arm only. `migrate-and-test` and `test-isolated` are separate arms and do not reach it — correct, since `migrate-and-test` is the documented auto-rebuild path, and `./sb migrate up` asks the same question itself on every run.

**Refuses rather than warns.** Matching its siblings. A warning would print to someone already looking at a green suite and scrolling to the summary — and the entire failure mode is that nothing looks wrong. The refusal names both remedies (`./sb migrate redo <version>` for a WIP edit; forward repair migration per STATBUS-172 if the version is released), verified by reading `FormatContentHashRefusal` in `cli/internal/migrate/migrate.go`, so it is actionable rather than merely obstructive.

**Evidence.**
- GREEN — clean tree, `./sb assert-db-content-hash statbus_seed` → exit 0, silent.
- RED 1 — one applied migration edited in place (version unchanged, `8e22e97f` → `0fdab477`): refuses, exit 1, both remedies printed.
- RED 2 (end-to-end) — **pending**, see below.

**RED 2 was masked, and I am not calling it proven.** The first end-to-end attempt refused for the *wrong reason*: the older `assert-db-at-head` fired first because the seed is BEHIND HEAD by `20260828231905` (STATBUS-312's reconstruction migration, untracked on disk, not yet in the seed). Control never reached my line. A reachability harness that neutralized only the predecessor gate in a throwaway root copy of `dev.sh` was then blocked twice by the test-run lock. The real end-to-end run is queued behind the in-flight `migrate-and-test fast`, which brings the seed to HEAD and makes the honest test possible.

**Near-miss worth recording.** My probe's guard pattern `dev\.sh test` does not match `dev.sh migrate-and-test`, so it mutated a shared migration file for ~2s while a migration run was live. No damage — that run was already past migrate-up, and `20240102000000` applied cleanly at restored bytes (`/tmp/migrate_and_test_312.log:40-42`) — but that is luck, not a guard. Both probes now refuse to mutate while any migration/seed command is live. The lesson is the ticket's own lesson one level up: a check whose pattern matches nothing passes silently.

Probes: `tmp/313-red-probe.sh`, `tmp/313-red2-reachability.sh` (tmp/, not for commit). Both restore byte-identically via `cp` — no git index, no stash, no checkout.
---
<!-- COMMENTS:END -->
