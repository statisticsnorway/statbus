---
id: STATBUS-231
title: >-
  vm-create-retry-scope: a temporary "no capacity" answer from Hetzner fails a
  scenario instantly — the create retry only covers the account-limit error
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-18 10:54'
updated_date: '2026-08-18 12:02'
labels:
  - install-recovery
  - ci
  - infra
dependencies: []
references:
  - test/install-recovery/lib/vm-bootstrap.sh
  - tmp/operator-ir-triage-2026-08-18.md
priority: medium
type: enhancement
ordinal: 231000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Test scenarios rent a machine each; when the provider momentarily has none to give, the right response is to wait and ask again — the shortage clears in minutes. Today two scenarios failed instantly instead, costing their coverage for the whole run.

WHAT THE EVIDENCE SHOWS: at the rc.03 install-recovery run (32115159128), both 0-happy scenarios died 48 seconds in at `hcloud server create` with "error during placement (resource_unavailable)" — Hetzner had no capacity to place the VM at that moment, likely because the run's first provisioning wave asked for several at once. The failure was loud and honest (the message names the cause; not the 227 starvation class, not a cancellation). But the create retry added in the fleet hardening (5 attempts x 60s) triggers ONLY on the literal `resource_limit_exceeded` string — the account-quota error — so this different, equally-transient error skipped the retry entirely.

THE FIX: widen the retry trigger to also match placement `resource_unavailable` (and consider whether any other transient hcloud error classes belong; permanent errors like auth failures must still fail fast). Same bounded retry, no new machinery.

WHAT IS ACHIEVED: a minutes-long capacity blip at the provider costs a scenario a short wait instead of its whole verdict — fewer red runs that mean nothing about the product.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The create retry fires on placement resource_unavailable as well as resource_limit_exceeded; permanent error classes still fail fast
- [ ] #2 A scenario surviving a transient placement shortage is observed (or the retry path is test-pinned if observation is impractical)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-18 11:36
---
RAISED TO MEDIUM AND FOLDED INTO THE MECHANIC'S IN-FLIGHT 227 UNIT (same file, vm-bootstrap.sh): THIRD placement resource_unavailable in one day — the two 0-happy install-recovery baselines this morning, and now the rc.03 spot-check's working arc (run 32131797267, job failed at hcloud server create with the identical error class; everything on our side of the create worked). The gap now has a demonstrated cost: it burned a spot-check VM slot and a verdict. Fix as filed: widen the bounded create-retry trigger to placement resource_unavailable alongside resource_limit_exceeded; permanent classes still fail fast.
---

author: mechanic
created: 2026-08-18 12:00
---
Folded into the in-flight STATBUS-227 unit (same file, test/install-recovery/lib/vm-bootstrap.sh), frozen together, no commits.

AC#1: the create-retry's trigger check changed from `grep -q "resource_limit_exceeded"` to `grep -qE "resource_limit_exceeded|resource_unavailable"` — same bounded 5x60s retry loop, same fail-fast for anything else (bad image, auth, other quota classes untouched — still return 1 immediately on the first non-matching error). Updated the two surrounding comments (the retry-block header and the STATBUS-207 ownership-guard note just below it) to name both transient classes and the 3x-in-one-day evidence (both 0-happy install-recovery baselines + the rc.03 spot-check's working arc, run 32131797267) instead of only resource_limit_exceeded. The retry/backoff log lines now say "a transient capacity error" generically and echo the raw hcloud error text on each retry, so which specific class fired is still visible in the job log for future triage.

AC#2: not test-pinned — flagging why rather than silently skipping it. This repo has no bash-level test harness (no bats/shunit2, checked: zero `.bats` files anywhere, no existing test wrapping vm-bootstrap.sh's functions) for unit-testing a shell retry loop in isolation; building one from scratch for this single check is disproportionate scope for a same-file fold-in, and the existing resource_limit_exceeded half of this same retry loop was never test-pinned either when it shipped (STATBUS-208). Given the failure class recurred 3x in one day, observation at the next live suite is the realistic verification path here, consistent with how resource_limit_exceeded's own retry was validated. Your call whether a dedicated bash test harness is worth standing up as its own ticket.

Validated: bash -n clean, shellcheck diffed against the pre-fold baseline — zero new findings (part of the same clean re-diff reported on STATBUS-227's comments).
---

author: foreman
created: 2026-08-18 12:02
---
LANDED at 07138b2c4 inside the 227 unit. AC#1 closed: the retry fires on both transient classes, permanent classes still fail fast. AC#2's ruling (architect, 227 comment #7): deliberately NOT test-pinned — a unit test over a provider's error phrasing would pin a snapshot of vocabulary we don't control; the MECHANISM is the per-attempt raw-error echo (a new transient class names itself in the log), and the next live suite is the observation. No bash-test-harness ticket — infrastructure justified by demand across many tests, not one grep. Stays In Progress on the AC#2 observation.
---
<!-- COMMENTS:END -->
