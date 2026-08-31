---
id: STATBUS-330
title: >-
  bootstrap-fetch-errors: install.sh's own git fetch still speaks raw git at the
  operator — delegate to ./sb when it exists, name the true residue
status: Done
assignee: []
created_date: '2026-08-31 12:58'
updated_date: '2026-08-31 20:55'
labels:
  - install
  - ops
dependencies: []
modified_files:
  - install.sh
  - cli/cmd/repo_fetch.go
  - cli/cmd/root.go
  - cli/cmd/bootstrap_fetch_delegation_test.go
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
- [x] #1 install.sh delegates its fetch to ./sb when the binary exists; raw git only when it is genuinely absent
- [x] #2 No second translator: the bash side contains no git-error text-matching
- [x] #3 The fresh-box residue is documented in install.sh at the fallback site (bootstrapping-order reasoning)
- [x] #4 The binary-procurement-order check is resolved and recorded (does anything narrow the residue further)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-31 20:52
---
BUILD FROZEN (unstaged, foreman commits).

## AC#4 first — the procurement-order check, and it corrects the ticket's premise

The ticket assumed "on a truly fresh box the first fetch precedes the product's existence". Reading the three paths, that is not what install.sh does. There are exactly two `git fetch` call sites, and the fresh release box is not one of them:

- **Fresh release/channel install** (`install.sh:472-491`) — `git clone --depth 1 --branch <tag>` at 475. It **never fetches**. There is no fresh-box residue on this path because there is no fetch on this path.
- **Rescue** (`install.sh:434-471`, `$STATBUS_DIR/.git` already present) — the binary is downloaded to `${HOME}/sb.tmp` at 431 and **moved into `$STATBUS_DIR/sb` at 437**, then the fetch runs at 461. The product is in place before the fetch, so this delegates. **This is the path gh's observed failure was on** — an existing slot, exactly as the ticket says.
- **`--commit`** (`install.sh:393-417`) — clone at 403, fetch at 409, checkout at 414, and `VERSION` is only derived from the checked-out HEAD at 419. Procurement pulls an image tagged with the `commit_short`, which cannot be known until after this fetch. No product can exist yet.

**So the residue is smaller than assumed and lives somewhere else than assumed: it is the `--commit` path only, not the fresh box.** The architect's instinct in the ONE CHECK FIRST was right — procurement order does narrow it — and the narrowing is total on the release path.

## What is built

**`cli/cmd/repo_fetch.go`** (new) — hidden `repo-fetch` verb. It DOES the fetch through `upgrade.RunCommandOutput`, so `explainGitFailure` applies because the product's own exec path performed it. This is not the filter verb the architect rejected: nothing here reinterprets another command's output after the fact.

**`cli/cmd/root.go`** — `"sb repo-fetch": true` in `readOnlyCommandPaths`. Load-bearing, not tidy: `isMutatingCommand` defaults to mutating, and the staleness guard hard-fails mutating commands when the binary's commit disagrees with the worktree. That disagreement IS the normal mid-rescue state — binary placed at 437, tree checked out at 466 — so without the registration the command would refuse at precisely the moment install.sh calls it.

**`install.sh`** — `statbus_git_fetch()` with two branches (installed binary, else raw git), and both call sites converted.

## A branch I built, then deleted after checking

My first version had a third branch reaching for `${HOME}/sb.tmp` — the downloaded-but-not-yet-moved binary — justified by a comment claiming the release path downloads before the clone and so a fresh install could delegate too. Reading the call sites disproved it: the rescue path moves the binary before it fetches, and the fresh path does not fetch at all. **No call site can be in that state.** It was defensive cover for a situation the script cannot reach, and worse, the comment asserted an ordering the script does not have. Deleted, with the deletion and its reason recorded at the helper so it is not re-added.

## Tests — `cli/cmd/bootstrap_fetch_delegation_test.go` (new), 7 tests

- AC#1 — every executable `git fetch` delegates, except the one fallback inside the helper. (First version flagged install.sh's operator-facing *error message* at 410, which merely names the command; the assertion now distinguishes an invocation from a mention.)
- AC#1 — the product is preferred and raw git is last.
- **The rescue-path ordering** — `mv` into place must precede its fetch. If those two are ever reordered the delegation silently degrades to raw git on the one path built for it, with no error anywhere, because the fallback is legitimate elsewhere. Pinned rather than left to be noticed.
- AC#2 — no git-error text fragments in any executable bash line.
- AC#3 — the residue explanation names `--commit` and `commit_short`, so the reader learns WHICH path cannot delegate and why; the fallback line itself is marked GENUINE RESIDUE. (This test caught me dropping the word from the preamble during the rewrite above.)
- `repo-fetch` is registered read-only, and is Hidden.

`bash -n` clean, `gofmt -l` clean, `go vet ./...` clean, 7/7 green.
---

author: engineer
created: 2026-08-31 20:53
---
ADDENDUM — the full Go suite caught this unit colliding with STATBUS-323's guard, and where the helper is DEFINED turned out to be load-bearing.

`TestRepoLockAcquiredBeforeAnyRepoOperation` (cli/cmd/install_quiesce_order_test.go:25) failed:

    "git fetch" runs at line 293, BEFORE the lock acquisition at line 308 — it
    can be raced by the service's discovery fetch

The guard scans install.sh for a repo operation appearing above the lock acquisition. It reads LINES, not executions — so the `git fetch` inside `statbus_git_fetch`'s body counted as a pre-lock repo operation, even though a function definition runs nothing. I had placed the helper next to the lock-contract comment block, which is above the acquisition.

**I did not adjust the guard.** Teaching it to skip function bodies would have made this unit pass and simultaneously blinded it to a real repo operation someone later parks inside a function — the guard exists because ma lost that exact race (`cannot lock ref 'refs/remotes/origin/master'`). Weakening a race guard so my own change fits is the wrong direction.

Instead the helper is now DEFINED immediately after `statbus_repo_lock_acquire`, with a comment saying why it sits there and not with the other helpers. Both call sites are far below, so nothing is lost, and the guard stays exact.

Worth noting for the reviewer: the guard's imprecision is real but benign in this direction — it can only produce false REFUSALS, never false passes. That is the correct bias for a race guard, so I am leaving it alone rather than filing a follow-up.

Final state of the frozen unit — `bash -n` clean, `gofmt -l` clean, `go vet ./...` clean, full `go test ./...` green (the run that surfaced this is the same run that now passes).
---

author: engineer
created: 2026-08-31 20:54
---
LINE-NUMBER CORRECTION for comment #1. Moving the helper below the lock acquisition (comment #2) shifted everything under it by 12 lines, so the citations in comment #1 are stale. They were accurate when written; these are the numbers in the frozen tree:

- **`--commit`** — clone 416, fetch 422, checkout 427, `VERSION="$(git rev-parse --short=8 HEAD)"` 432. The version the image tag is built from is only known at 432, ten lines after the fetch it would have had to translate. This is the residue.
- **Rescue** — download 444, `mv "${HOME}/sb.tmp" "${STATBUS_DIR}/sb"` **450**, delegated fetch **474**. Binary in place 24 lines before the fetch, so this delegates. `TestTheRescueFetchIsReachedWithTheBinaryInPlace` pins exactly this pair.
- **Fresh release** — `git clone --depth 1 --branch "$VERSION"` 488, `mv` 500. No fetch anywhere on this path.

The helper itself is at 360 (definition) with the lock acquired at 316. Nothing about the finding changes — only the coordinates.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LANDED at 4cd0bfc2f (foreman-reviewed; seven tests re-run independently; bash -n clean). install.sh's fetches delegate to a hidden ./sb repo-fetch verb — the delegation form the architect ruled, not the rejected filter surface: the verb DOES the fetch, so the 324 translator's quality arrives because the product performed the operation. Registered read-only (load-bearing: the staleness guard would otherwise hard-refuse at exactly the mid-rescue moment install.sh calls it — new binary placed, tree not yet checked out) and hidden (an internal delegation target, not an operator command). THE PREMISE CORRECTED (AC#4's procurement-order check): a fresh release install CLONES and never fetches — no residue there at all; the rescue path (where gh's observed failure lived) has the binary in place before its fetch and delegates fully; the ONLY raw-git fallback is --commit, where the product structurally cannot exist yet (its image tag derives from the commit being fetched) — documented at the fallback site as bootstrapping order, per AC#3. No bash git-error text-matching anywhere (test-pinned, AC#2). Process notes on record: the engineer built, disproved against the call sites, and DELETED a third branch reaching for the not-yet-moved binary (dead cover for an unreachable state); and placed the helper below the repo-lock acquisition so STATBUS-323's line-scanning race guard stayed exact rather than being taught to skip function bodies (a scanner that skips bodies also stops seeing real repo operations parked in one — false refusals are the right bias for a race guard). Also owned honestly: a start announced in the 328 report that had not actually begun, caught by the foreman's status check.
<!-- SECTION:FINAL_SUMMARY:END -->
