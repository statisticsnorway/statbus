---
id: STATBUS-330
title: >-
  bootstrap-fetch-errors: install.sh's own git fetch still speaks raw git at the
  operator — delegate to ./sb when it exists, name the true residue
status: To Do
assignee: []
created_date: '2026-08-31 12:58'
labels:
  - install
  - ops
dependencies: []
priority: low
type: enhancement
ordinal: 323000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the site where the misleading failure was actually OBSERVED speaks as clearly as every other site. STATBUS-324's translator (7473cddfb) covers all Go-side git invocations — but gh's observed failure happened in install.sh's OWN `git fetch`, which surfaces git's text straight to the operator. Ruled TICKET by the architect (2026-08-31), with the shape chosen and the residue named.

THE SHAPE (architect's ruling): prefer DELEGATION over a filter verb. A `./sb explain-git-failure` pipe would add a public surface whose only job is reinterpreting another command's output. Cleaner: when ./sb exists, install.sh DELEGATES the fetch to it — one implementation of fetch-with-good-errors, reusing the landed translator (explainGitFailure in cli/internal/upgrade/exec.go), the same delegate-rather-than-duplicate reasoning as 283. Fall back to raw git only when ./sb is genuinely absent.

WHY DELEGATION REACHES THE OBSERVED CASE: gh is an EXISTING slot — its bootstrap fetch ran with ./sb present. The case a delegation closes is exactly the case that was reported.

THE TRUE RESIDUE, ACCEPTED EXPLICITLY: on a truly fresh box the first fetch precedes the product's existence and cannot be translated by the product without duplicating it — a consequence of bootstrapping order, not an oversight. One comment in install.sh must SAY so, or the next reader files this ticket again.

ONE CHECK FIRST (architect): binary procurement is a docker pull, not a repo operation — if it already precedes the clone in install.sh's order, even the fresh-box residue may be smaller than assumed. Resolve and record before building.

WHAT IS ACHIEVED: the originating complaint's site is fixed, one translator exists in exactly one place, and the unavoidable gap is a documented consequence of bootstrap order rather than a rediscoverable surprise.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 install.sh delegates its fetch to ./sb when the binary exists; raw git only when it is genuinely absent
- [ ] #2 No second translator: the bash side contains no git-error text-matching
- [ ] #3 The fresh-box residue is documented in install.sh at the fallback site (bootstrapping-order reasoning)
- [ ] #4 The binary-procurement-order check is resolved and recorded (does anything narrow the residue further)
<!-- AC:END -->
