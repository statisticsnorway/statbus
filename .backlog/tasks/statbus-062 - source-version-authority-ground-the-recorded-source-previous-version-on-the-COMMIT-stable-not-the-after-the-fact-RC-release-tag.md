---
id: STATBUS-062
title: >-
  source-version-authority: ground the recorded source/previous version on the
  COMMIT (stable), not the after-the-fact RC/release tag
status: In Progress
assignee: []
created_date: '2026-06-16 09:49'
updated_date: '2026-06-16 10:09'
labels:
  - upgrade
  - recovery
  - foundational
  - king-decision
  - architect-plan
dependencies: []
references:
  - >-
    doc-012 -
    STATBUS-062-design-ground-the-rollback-restore-target-on-the-CommitSHA.md
  - cli/internal/upgrade/commit.go
  - cli/internal/upgrade/service.go
priority: high
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUNDATIONAL DESIGN PRINCIPLE (King, 2026-06-16). DISCUSS + run by King before any implementation.

## Principle
The COMMIT (SHA) is the authoritative, STABLE identity of a version. A single commit MAY later be tagged a release candidate (vX-rc.N) and later a release (vX) — but those tags are assigned AFTER THE FACT and are NOT stable: a commit can be untagged when an upgrade starts and tagged later; tags can move or be pruned. Anywhere we record "the source/previous version" (for rollback/recovery), ground it on the COMMIT, not a tag/version-string.

## Current state (verified 2026-06-16, file:line)
- executeUpgrade records `from_commit_version = d.version` — a VERSION-STRING/tag (e.g. "v2026.05.2"), NOT a commit — at the scheduled→in_progress transition: service.go:1308 (ExecuteUpgradeInline) + service.go:3478 (executeScheduled). v2026.05.2's equivalent: service.go:1286 @ tag v2026.05.2 (commit 50fd4325).
- recoveryRollback (service.go:~2190) reads from_commit_version → `prev`; restoreGitStateFn (service.go:~5388) resolves `prev` as a git ref via `git rev-parse --verify <ref>^{commit}`, falling back to the `pre-upgrade` branch if it does not resolve.
- The column is NAMED `from_commit_version` but HOLDS a version-string — name/content mismatch. The tag-resolution + pre-upgrade-fallback fragility exists PRECISELY because we store a tag rather than a commit.

## Decision to run by King
1. Re-ground `from_commit_version` (and the recovery restore target) on the COMMIT SHA — always resolves, no tag fragility — keeping d.version (the tag/version-string) only for display? Or store BOTH (commit = authoritative restore anchor; version-string = display)?
2. Recovery restore target then resolves to the COMMIT directly (the `pre-upgrade` branch becomes pure defense-in-depth, not the load-bearing path).
3. Harness split: the GENUINE-v2026.05.2 legacy scenario (2-preswap-checkout-kill-legacy.sh) must still reproduce what v2026.05.2 ACTUALLY wrote (a version-string) — that is a historical fact, fidelity. But the HEAD/current scenarios + the go-forward product ground on the commit. Confirm this split.

## Why it matters now
Blocks finalizing STATBUS-061 part (iv)'s harness value (version-string vs commit) WITHOUT churn — see STATBUS-061. The architect (already on 061) folds the confirmed direction into the recovery fix; foreman reviews; run by King before code.

## Status
DESIGN — awaiting King's direction. Then architect designs the precise change (product + recovery + harness), run by King before implementation.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
KING RATIFIED + ASSIGNED to architect 2026-06-16: ground the rollback restore target on the CommitSHA (authoritative identity), not the CommitVersion (display-only). HARD REQUIREMENT — use the canonical typed vocabulary, no loose terms (King: unclear terms are the bane of confusion): cli/internal/upgrade/commit.go (SOLE source of truth) + doc/canonical-commit-naming.md, enforced by TestGuards_UseTypedFields. Types: CommitSHA (40-char, AUTHORITATIVE identity, =commit_sha), CommitShort (8-char display + CI image tag), CommitVersion (git-describe output; 'human-facing labels; NEVER for equality or lookup'), ReleaseTag (CalVer v-tag). THE BUG in these terms: from_commit_version stores d.version = a CommitVersion (never-for-lookup) but recoveryRollback uses it for a git-checkout lookup → violates the discipline. FIX direction: executeUpgrade records the SOURCE CommitSHA for rollback; consider renaming from_commit_version→from_commit_sha (clean break; the name lies today) or add from_commit_sha; keep CommitVersion for display only; recoveryRollback resolves restore from the CommitSHA (pre-upgrade branch = pure defense-in-depth); back-compat/migration for existing rows; route via commit.go smart constructors (no new shape predicates). Architect delivers (1) glossary note + (2) design → foreman→King review BEFORE code. Composes with STATBUS-061 rc.04 (iii) (prev="" → pre-upgrade).

2026-06-16 architect — DESIGN READY: doc-012. Approach = SOURCE pair mirroring the existing TARGET pair: ADD from_commit_sha (CommitSHA, authoritative restore anchor, CHECK 40-hex) + KEEP from_commit_version (CommitVersion, display). Capture from_commit_sha=NewCommitSHA(git rev-parse HEAD) at the claim (service.go:1308/3498; tree is at SOURCE — checkout deferred per STATBUS-060). Restore target reads from_commit_sha (recoveryRollback:2200, resumePostSwap:4616, in-process previousVersion:3857), never the CommitVersion; restoreGitStateFn unchanged → pre-upgrade demotes to defense-in-depth. Dissolves the 061 (a)-checkout-kill hazard (from_commit_sha=git HEAD=OLD, binary-version-independent) and SUBSUMES the held rc.04 (iii). Legacy rows: from_commit_sha NULL → pre-upgrade fallback, no backfill. TWO KING DECISIONS: (1) ADD column (rec) vs RENAME; (2) fold into current RC (rec) vs ship 062 as next RC. Reported to foreman; awaiting King ruling before code.

NOMENCLATURE PRECISION FINDING (foreman-verified live, 2026-06-16): d.version (the cmd.version ldflag, stored in public.upgrade.from_commit_version) is V-STRIPPED. Evidence: `./sb --version` → 'sb version 2026.06.0-rc.02-82-ga04b79e3a (commit a04b79e3)' — NO v. Build strips it (cli/Makefile:4 + dev.sh:62: `git describe ... | sed 's/^v//'`); display re-adds the v by convention (dev.sh:58 comment).

INCONSISTENCY to fix as part of ratification: cli/internal/upgrade/commit.go DOCUMENTS CommitVersion WITH the v (examples 'v2026.04.0-rc.61', 'v2026.04.0-rc.61-3-g61e79e26'), but the actual stored CommitVersion is V-STRIPPED — the type's doc disagrees with the type's value. This misled the mechanic (part-iv comment said 'v2026.05.2'; the real value is '2026.05.2'). Reconcile commit.go's CommitVersion definition to state v-stripped (display adds the v).

CONSEQUENCE: a stored CommitVersion ('2026.05.2') does NOT resolve as a git ref (the tag is 'v2026.05.2') → genuine-legacy rollback reaches OLD only via the pinned pre-upgrade branch — the exact fragility that motivates grounding on the CommitSHA.

GROUNDING (architect recommendation, pending King): capture the SOURCE CommitSHA as `git rev-parse HEAD` at the scheduled→in_progress CLAIM (the tree is still at source pre-defer-checkout, so HEAD = the true source CommitSHA — NOT d.binaryCommit, which = TARGET in a HEAD-recovery). Store in a NEW from_commit_sha column (keep from_commit_version for display only). Bonus: also fixes the (a) checkout-kill resolving-TARGET risk for free. AWAITING King's nomenclature approval before any propagation.
<!-- SECTION:NOTES:END -->
