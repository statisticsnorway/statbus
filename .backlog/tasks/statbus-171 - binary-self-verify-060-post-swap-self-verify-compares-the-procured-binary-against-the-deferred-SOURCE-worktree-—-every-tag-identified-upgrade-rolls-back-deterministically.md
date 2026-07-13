---
id: STATBUS-171
title: >-
  binary-self-verify-060: post-swap self-verify compares the procured binary
  against the deferred SOURCE worktree — every tag-identified upgrade rolls back
  deterministically
status: To Do
assignee:
  - '@engineer'
created_date: '2026-07-13 01:40'
labels:
  - upgrade
  - production
  - fail-fast
dependencies: []
priority: high
ordinal: 172000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the binary-replace step verifies the procured binary against the UPGRADE TARGET — the one fact it exists to check — never against a worktree that STATBUS-060 deliberately leaves at the source.
> FOUND: 2026-07-13 night, dev row 331014 (rc.02 attempt): BINARY_REPLACE_FAILED, "self-verify failed: exit status 2 / procured binary is still reported stale / will fail the same way" — deterministic rollback at 01:23:16 after a correct schedule and claim.
> COMPLEXITY: engineer — mirror the adjacent manifest check's existing 060 fix; unit test + a real VM/deploy run as the oracle. THE FLEET BLOCKER: no tag-identified upgrade can complete until the fixed binary is the TARGET (the fix rides in the target's own stalenessGuard, so the first release carrying it heals the path).

THE MECHANISM (traced on dev evidence + code):
1. STATBUS-060 DEFERS the working-tree checkout: during binary-replace the tree is still at the SOURCE commit (17d47c5e on dev), by design — the old binary must not see the target's compose (service.go:5040-5058).
2. replaceBinaryOnDisk procures the TARGET binary (49b2e6ea) and invokes it as a SELF-VERIFY. The new binary's stalenessGuard (root.go) compares ITS embedded commit against `git rev-parse HEAD` — the deferred SOURCE — 49b2e6ea ≠ 17d47c5e → "stale" → self-heal re-procures → still "stale" → exit 2 (root.go:183) → BINARY_REPLACE_FAILED → rollback. Deterministic.
3. THE TELL: the manifest-tampering check ONE BLOCK ABOVE (service.go:5052-5071) already carries the 060 fix — it compares against the upgrade target's commit explicitly BECAUSE "the working-tree checkout is deferred". The self-verify is the sibling that never got the same fix.

FIX SHAPE (architect to ratify): the self-verify verifies the procured binary embeds the TARGET commit — mirroring the manifest check's 060 fix — instead of invoking the stalenessGuard-against-worktree-HEAD. OPEN QUESTION the build must settle with a test: does this break EVERY tag-identified upgrade post-060 (likely) or is there a condition (dev reached 17d47c5e commit-identified successfully the same night — name why the commit path survives, or whether it also only survived circumstantially).

WHY THE FIX CONVERGES THE FLEET: the failing comparison runs INSIDE the target binary — so the first release whose binary carries the fix self-verifies correctly, and every box upgrades to it normally. dev (edge) converges on the fix landing on master + a deploy-pointer push; Norway and the release fleet on the next RC (plus Norway's one-tap bootstrap, STATBUS-169).

RELATION: found while tracing the 169-adjacent dev retry (scheduler and STATBUS-160 both proven CORRECT by the row timeline); the deploy-green-vs-converged gap is STATBUS-170.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The self-verify compares the procured binary's embedded commit against the UPGRADE TARGET (the manifest check's 060 pattern); the stalenessGuard-vs-source path is removed from this call site
- [ ] #2 Unit test pins it: a target binary verifying against a source-checkout worktree passes when its embedded commit equals the target (and fails when it does not)
- [ ] #3 The commit-path survival question is answered with evidence: why did commit-identified upgrades succeed the same night — condition named, or also-broken documented
- [ ] #4 Proven live: dev completes a tag-identified upgrade through the normal path (the run is the oracle)
<!-- AC:END -->
