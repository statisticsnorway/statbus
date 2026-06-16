---
id: STATBUS-062
title: >-
  source-version-authority: ground the recorded source/previous version on the
  COMMIT (stable), not the after-the-fact RC/release tag
status: In Progress
assignee: []
created_date: '2026-06-16 09:49'
updated_date: '2026-06-16 10:20'
labels:
  - upgrade
  - recovery
  - foundational
  - king-decision
  - architect-plan
dependencies: []
references:
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## DESIGN (folded from doc-012; ticket is the single source). Foreman concurred ADD + FOLD-IN; awaiting King's nomenclature approval + rulings. HOLD code.

### Glossary — exact terms (cli/internal/upgrade/commit.go, sole source of truth)
- CommitSHA — 40-char hex. AUTHORITATIVE identity; equality = same commit; the ONLY legal lookup/checkout key. SQL public.upgrade.commit_sha (CHECK ^[a-f0-9]{40}$). Ctor NewCommitSHA.
- CommitShort — 8-char hex. Display abbrev + CI Docker image tag. NEVER equality/lookup.
- CommitVersion — `git describe --tags --always` output. Human label only; NEVER equality/lookup. ⚠ V-PREFIX INCONSISTENCY (verified 2026-06-16): the DB column commit_version is V-PREFIXED (service.go:2906/2919 writes the GitHub tag verbatim, "v2026.05.2"), but the binary d.version is V-STRIPPED (Makefile:4/dev.sh:62 `sed 's/^v//'`). git-describe + ReleaseTag are natively v-prefixed; the binary's strip is the lone outlier. → commit.go's v-prefixed doc is CORRECT for the DB/git form. NOMENCLATURE SUB-DECISION (King): X = v-prefixed canonical (binary stops stripping) vs Y = v-stripped canonical (DB capture strips + doc→stripped). DISPLAY-ONLY; independent of the restore-target fix. Architect leans X. HOLD the commit.go-doc edit until ruled.
- ReleaseTag — CalVer `vYYYY.MM.patch[-suffix]`.

### The bug (in these terms)
from_commit_version holds a CommitVersion (d.version) but is used as the git-checkout restore target (a LOOKUP) in two roots: recoveryRollback (service.go:2200) and executeUpgrade's `previousVersion := d.version` (3857, feeding all in-process d.rollback/postSwapFailure/applyPostSwap + resumePostSwap:4616). CommitVersion-for-lookup violates the discipline; it's why "2026.05.2" doesn't resolve and why d.version=TARGET restored FORWARD in a HEAD-recovery (061 finding 1).

### Fix — a SOURCE pair mirroring the existing TARGET pair (commit_sha + commit_version)
1. Schema (migration): ADD from_commit_sha text + CHECK (from_commit_sha IS NULL OR ~ ^[a-f0-9]{40}$), mirroring chk_upgrade_commit_sha_is_full_hex. KEEP from_commit_version (display). Regenerate doc/db/table/public_upgrade.md same commit. [King decision 1: ADD (foreman+architect rec) vs RENAME.]
2. Capture (write): at the claim (ExecuteUpgradeInline service.go:1308, executeScheduled :3498) record from_commit_sha = NewCommitSHA(git rev-parse HEAD). Tree is at SOURCE there (target checkout deferred to recovery boot, STATBUS-060) = the same commit pre-upgrade pins (3841). Keep from_commit_version = d.version (display).
3. Restore target reads the CommitSHA, never the CommitVersion: in-process previousVersion := string(sourceSHA) (3857); recoveryRollback (2200) reads from_commit_sha→prev (NewCommitSHA), prev:="" default→pre-upgrade — SUBSUMES held rc.04 (iii); resumePostSwap (4616) reads from_commit_sha→previousVersion.
4. restoreGitStateFn (5381) unchanged: a CommitSHA always resolves → pre-upgrade branch demotes to pure defense-in-depth.
5. Display untouched: from_commit_version stays for admin UI "From:" (app/src/app/admin/upgrades/page.tsx:1225) + fixup INSERT (cli/cmd/install.go:1932). Optional: add from_commit_sha to that INSERT for symmetry (low priority).
Vocab-compliant: route through NewCommitSHA; no new shape predicate; TestGuards_UseTypedFields green.

### Payoffs
- Dissolves the 061 (a)-checkout-kill hazard: from_commit_sha = git HEAD at claim = OLD (the tree), binary-version-independent → (a) recovers to OLD deterministically.
- SUBSUMES the held rc.04 (iii).
- Back-compat, NO backfill: legacy rows from_commit_sha NULL → prev:="" → pre-upgrade fallback (pinned by the OLD binary mid-upgrade) → OLD. Down: drop from_commit_sha.

### Harness split (King option 3)
- 2-preswap-checkout-kill-legacy.sh (genuine v2026.05.2): reproduce what v2026.05.2 ACTUALLY wrote — from_commit_version="2026.05.2" (CommitVersion), from_commit_sha NULL → validates HEAD recovering a LEGACY row via pre-upgrade fallback (fidelity).
- HEAD/go-forward scenarios (part iv): from_commit_sha = source commit → validates the commit-grounded path.

### Sequencing [King decision 2]: A (recommended) = fold into the current recovery RC (both scenarios clean, (a) dissolved, (iii) subsumed) vs B = ship current RC behavior-only now, 062 as next RC.

### Critical files
service.go: claim 1308+3498 (write from_commit_sha); previousVersion:=d.version 3857; recoveryRollback 2200; resumePostSwap 4616; restoreGitStateFn 5381 (unchanged); pre-upgrade pin 3841; discovery commit_version capture 2906 (v-prefix). migrations/ new pair + doc/db regen. commit.go NewCommitSHA (+ CommitVersion doc, pending nomenclature ruling). Display: page.tsx:1225, install.go:1932.

### Verification
migrate up/down clean; go test ./internal/upgrade ./internal/install ./internal/config; TestGuards_UseTypedFields green; 0-happy + both 2-preswap green; admin "From:" still renders.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
KING RATIFIED + ASSIGNED to architect 2026-06-16: ground the rollback restore target on the CommitSHA (authoritative identity), not the CommitVersion (display-only). HARD REQUIREMENT — use the canonical typed vocabulary, no loose terms (King: unclear terms are the bane of confusion): cli/internal/upgrade/commit.go (SOLE source of truth) + doc/canonical-commit-naming.md, enforced by TestGuards_UseTypedFields. Types: CommitSHA (40-char, AUTHORITATIVE identity, =commit_sha), CommitShort (8-char display + CI image tag), CommitVersion (git-describe output; 'human-facing labels; NEVER for equality or lookup'), ReleaseTag (CalVer v-tag). THE BUG in these terms: from_commit_version stores d.version = a CommitVersion (never-for-lookup) but recoveryRollback uses it for a git-checkout lookup → violates the discipline. FIX direction: executeUpgrade records the SOURCE CommitSHA for rollback; consider renaming from_commit_version→from_commit_sha (clean break; the name lies today) or add from_commit_sha; keep CommitVersion for display only; recoveryRollback resolves restore from the CommitSHA (pre-upgrade branch = pure defense-in-depth); back-compat/migration for existing rows; route via commit.go smart constructors (no new shape predicates). Architect delivers (1) glossary note + (2) design → foreman→King review BEFORE code. Composes with STATBUS-061 rc.04 (iii) (prev="" → pre-upgrade).

2026-06-16 architect — DESIGN READY: doc-012. Approach = SOURCE pair mirroring the existing TARGET pair: ADD from_commit_sha (CommitSHA, authoritative restore anchor, CHECK 40-hex) + KEEP from_commit_version (CommitVersion, display). Capture from_commit_sha=NewCommitSHA(git rev-parse HEAD) at the claim (service.go:1308/3498; tree is at SOURCE — checkout deferred per STATBUS-060). Restore target reads from_commit_sha (recoveryRollback:2200, resumePostSwap:4616, in-process previousVersion:3857), never the CommitVersion; restoreGitStateFn unchanged → pre-upgrade demotes to defense-in-depth. Dissolves the 061 (a)-checkout-kill hazard (from_commit_sha=git HEAD=OLD, binary-version-independent) and SUBSUMES the held rc.04 (iii). Legacy rows: from_commit_sha NULL → pre-upgrade fallback, no backfill. TWO KING DECISIONS: (1) ADD column (rec) vs RENAME; (2) fold into current RC (rec) vs ship 062 as next RC. Reported to foreman; awaiting King ruling before code.

NOMENCLATURE PRECISION FINDING (foreman-verified live, 2026-06-16): d.version (the cmd.version ldflag, stored in public.upgrade.from_commit_version) is V-STRIPPED. Evidence: `./sb --version` → 'sb version 2026.06.0-rc.02-82-ga04b79e3a (commit a04b79e3)' — NO v. Build strips it (cli/Makefile:4 + dev.sh:62: `git describe ... | sed 's/^v//'`); display re-adds the v by convention (dev.sh:58 comment).

INCONSISTENCY to fix as part of ratification: cli/internal/upgrade/commit.go DOCUMENTS CommitVersion WITH the v (examples 'v2026.04.0-rc.61', 'v2026.04.0-rc.61-3-g61e79e26'), but the actual stored CommitVersion is V-STRIPPED — the type's doc disagrees with the type's value. This misled the mechanic (part-iv comment said 'v2026.05.2'; the real value is '2026.05.2'). Reconcile commit.go's CommitVersion definition to state v-stripped (display adds the v).

CONSEQUENCE: a stored CommitVersion ('2026.05.2') does NOT resolve as a git ref (the tag is 'v2026.05.2') → genuine-legacy rollback reaches OLD only via the pinned pre-upgrade branch — the exact fragility that motivates grounding on the CommitSHA.

GROUNDING (architect recommendation, pending King): capture the SOURCE CommitSHA as `git rev-parse HEAD` at the scheduled→in_progress CLAIM (the tree is still at source pre-defer-checkout, so HEAD = the true source CommitSHA — NOT d.binaryCommit, which = TARGET in a HEAD-recovery). Store in a NEW from_commit_sha column (keep from_commit_version for display only). Bonus: also fixes the (a) checkout-kill resolving-TARGET risk for free. AWAITING King's nomenclature approval before any propagation.

2026-06-16 architect — folded the full design into this ticket's plan (single source); doc-012 removed per foreman. NEW nomenclature finding flagged: CommitVersion v-prefix is INCONSISTENT — DB commit_version is v-PREFIXED (service.go:2906, GitHub tag verbatim) while binary d.version is v-STRIPPED (Makefile:4 sed). commit.go's v-prefixed doc is correct for the DB/git form; the binary strip is the lone outlier. Added as nomenclature sub-decision (X v-prefixed canonical [architect lean] vs Y v-stripped canonical). Display-only; the restore-target core (from_commit_sha) is unaffected. commit.go-doc edit HELD until King rules the convention.
<!-- SECTION:NOTES:END -->
