---
id: STATBUS-062
title: >-
  source-version-authority: ground the recorded source/previous version on the
  COMMIT (stable), not the after-the-fact RC/release tag
status: In Progress
assignee: []
created_date: '2026-06-16 09:49'
updated_date: '2026-06-16 10:01'
labels:
  - upgrade
  - recovery
  - foundational
  - king-decision
  - architect-plan
dependencies: []
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
<!-- SECTION:NOTES:END -->
