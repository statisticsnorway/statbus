---
id: STATBUS-369
title: >-
  the ladder never installs the candidate fresh: 0-happy-install installs the previous stable, so every release ships with its own install path unproven (v2026.09.0 fresh install fails)
status: In Progress
assignee: []
created_date: '2026-09-14 12:36'
updated_date: '2026-09-14 12:36'
labels:
  - release
  - install
  - fail-fast
dependencies: []
priority: high
type: bug
---

## The finding (observation, 2026-09-14)

`doc/release-ladder.md` line 21 says smoke `0-happy-install` proves "a fresh
Ubuntu VM runs the real install.sh and ends with a healthy StatBus **at the
candidate**". The script says otherwise, in its header and its code:

    # Fresh VM → install the newest stable release strictly below the target
    INSTALL_VERSION="${INSTALL_VERSION:-$(select_release_baseline_from_repo "$REPO_ROOT")}"
    install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

No scenario in `test/install-recovery/scenarios/` installs the candidate
itself (`grep commit_under_test scenarios/` finds nothing). Both smoke cells
start by installing the previous stable. So by induction: **every stable
release ships with its own fresh-install path unproven**; it is first
exercised when the NEXT candidate's ladder installs it as the baseline.

Log lines that show it (verbatim):

- rc.14 (green, 2026-09-04, install-recovery-harness job 0-happy-install):
  `Release selected for clean install: v2026.08.1` ...
  `Detected install state: half-configured (current=v2026.08.1, target=v2026.08.1)` ... `✓ health check passed`
- rc.04 (red, 2026-09-14, test-smoke run 34840110574):
  `Release selected for clean install: v2026.09.0` ...
  `Detected install state: fresh (current=v2026.09.0, target=v2026.09.0)` ...
  `[4/17] Configuration FAILED: .env.config not found`

So v2026.09.0, stable since 09-04 and running on Norway and Albania (both
by upgrade, never fresh), fails a fresh install on a harness-prepared box.
Whether that is a v2026.09.0 bug or the candidate's harness no longer
delivering `.env.config` is being split by one VM (hatchling, protocol in
`tmp/v20260900-fresh-install-investigation.md`).

Why it was missed: the scenario never asserted "installed version == the
candidate". A proof names its claim in an assertion, not in a comment.

## Work

1. **Cause** (in flight): VM observation, then either a fix in the candidate's
   install path (if v2026.09.0 has the bug, the candidate must not) or a
   harness fix.
2. **`0-happy-install` installs the candidate.** From the candidate's own
   release assets (`sb-linux-<arch>` at the tag, published images at the
   commit), via the real `install.sh`, on a fresh VM. Assert, in the
   scenario: `sb version` on the box equals the candidate tag; `public.upgrade`
   records the candidate; health passes. `0-happy-upgrade` keeps installing
   the previous stable (that IS its claim).
3. **Doc and code agree.** `doc/release-ladder.md` row 4 stays; the scenario
   header is rewritten to match. `install-works` in STATBUS-359's naming is
   this cell.
4. **`release covered` must not ride this cell across a version change**: a
   fresh install of X is evidence about X only.
5. Adversarial review; then this candidate's ladder runs the new cell and
   the fix together.

## Done when

The rc ladder for this batch shows `0-happy-install` installing the
candidate tag on a fresh VM and passing, and `0-happy-upgrade` installing
v2026.09.0 then upgrading to the candidate and passing. Both observed in
run logs and recorded here. A fresh `install.sh` of the resulting stable on
a clean box works (the next ladder's baseline hop confirms it, and so does
step 2 at that time).
