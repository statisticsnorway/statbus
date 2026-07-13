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
updated_date: '2026-07-13 02:01'
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
- [x] #3 The commit-path survival question is answered with evidence: why did commit-identified upgrades succeed the same night — condition named, or also-broken documented
- [ ] #4 Proven live: dev completes a tag-identified upgrade through the normal path (the run is the oracle)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (relayed by foreman)
created: 2026-07-13 01:45
---
RATIFIED (architect, 2026-07-13 night), reasoning stated precisely: the self-verify's question is "is the binary we just put on disk the one we INTENDED" — under 060's deferred checkout the intended identity is the TARGET commit (known at that site from the row/flag), while `git rev-parse HEAD` is deliberately the SOURCE. Comparing against HEAD there is a CATEGORY ERROR, not a wrong threshold. Dropping the stalenessGuard invocation at this call site is remove-wrong-paths, not weakening: stalenessGuard's binary-matches-worktree contract remains the right check at DAEMON BOOT (post-recovery-checkout, HEAD=target, the rc.65 class lives there) — that coverage is untouched; the mid-upgrade site gains the stronger, correct check.

TWO RIDERS: (1) the condition-vs-circumstance answer is PART OF THE UNIT — if commit-identified upgrades survive by STRUCTURE, the fix as shaped is complete; if by CIRCUMSTANCE (e.g. those schedules happened to equal the box's HEAD), the commit path carries the same latent bug and the target-identity verify must cover it in this same unit. Don't ship without knowing which; the answer lands as evidence + a comment at the fixed site. (2) Oracle = a tag-identified upgrade green end-to-end (row 331014's deterministic rollback is the RED half in hand — a complete red→green pair), plus one commit-identified re-run on the fixed binary proving no regression.

RECORD NOTE: row 331014's forecast told the operator 'this version will fail the same way — do NOT re-schedule' — for THIS bug the machinery was blaming the VERSION for its own defect. No text change needed (the advice is true for genuine version failures), but this stands as a known case where the forecast's attribution was wrong: the next investigator must not treat the forecast as evidence.
---

author: engineer (relayed by foreman)
created: 2026-07-13 02:01
---
ROOT-CAUSE TRACE COMPLETE (read-only; AC#3's verdict = STRUCTURAL, checked). The chain, all code-confirmed: tag upgrade → replaceBinaryOnDisk → selfupdate.go:89 execs `<newBinary> upgrade self-verify` → cobra PersistentPreRun stalenessGuard (root.go:62) → freshness.IsStale runs `git diff --quiet <newBinaryCommit> HEAD -- cli/` (check.go:214) — HEAD is the deferred SOURCE under 060 → stale → `upgrade self-verify` is in no exemption list → hard-exit 2 → BINARY_REPLACE_FAILED. Local reproduction: `git diff --quiet 49b2e6ea 17d47c5e -- cli/` → exit 1; the drifting files ARE STATBUS-169's. Deterministic by operands.

REFUTED: mis-built artifact (a stale hard-exit REQUIRES the binary's commit to resolve correctly — the symptom itself proves the right embed; the manifest anti-tamper check passed before the rollback) and procurement race (the 'race' phrase is the recursion-guard's generic hint text, root.go:181; the pure git-diff reproduces deterministically).

CONDITION-VS-CIRCUMSTANCE = STRUCTURAL (rider 1 satisfied): the fork is service.go:5095 ValidateVersion — tagged → replaceBinaryOnDisk → execs self-verify → guard; edge commit → buildBinaryOnDisk → procureSbFromImage (docker create/cp, never execs the new binary) → guard never runs mid-swap. The commit path is safe by construction; 171's fix is complete as shaped.

WHY NO ARC EVER CAUGHT IT (coverage-map fact, STATBUS-071-relevant): root.go:137 — STATBUS_INJECT_AT (set by the whole install-recovery harness) downgrades stalenessGuard to advisory WARN. The class is invisible to every arc BY CONSTRUCTION; only a real tag upgrade exposes it → the oracle must be the real dev tag re-dispatch (rider 2's plan; row 331014 is the RED half).

REFINED FIX (within the ratification): exempt `upgrade self-verify` from stalenessGuard via the freshness_probe annotation (root.go:89, the committed-drift pattern) AND make self-verify positively assert TARGET IDENTITY (embedded commit == expected target passed by the caller) — the manifest check's 060 pattern. Boot-time guard coverage untouched, stated at the site.

RECORDED RESIDUAL (flag, not folded): selfupdate.go:89 execs the child WITHOUT clearing env — it inherits freshness.SelfHealAttemptEnv (why row 331014 hit the recursion-guard branch rather than the plain hard-fail). Moot for self-verify once exempted; a latent sharp edge for any future child-exec — candidate follow-up, architect's morning call.
---
<!-- COMMENTS:END -->
