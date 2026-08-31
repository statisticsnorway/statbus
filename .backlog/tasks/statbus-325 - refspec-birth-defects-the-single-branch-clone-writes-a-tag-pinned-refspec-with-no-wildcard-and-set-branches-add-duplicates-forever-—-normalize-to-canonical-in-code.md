---
id: STATBUS-325
title: >-
  refspec-birth-defects: the single-branch clone writes a tag-pinned refspec
  with no wildcard, and set-branches --add duplicates forever — normalize to
  canonical, in code
status: To Do
assignee:
  - engineer
created_date: '2026-08-31 11:35'
labels:
  - install
  - ops
  - upgrade
dependencies: []
priority: high
type: bug
ordinal: 318000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a box's remote.origin.fetch is product-owned derived config — exactly canonical (wildcard heads + db-seed), regardless of how the box was born or how many times install ran. Today it is an accident of history: gh reached production with `+refs/tags/v2026.08.0-rc.16:refs/tags/v2026.08.0-rc.16`, db-seed tripled, and NO wildcard line — and its v2026.08.0 bootstrap fetch behavior depended on hand repair.

ROOT CAUSE, verified in current code (King's push: "maybe the script has a bug" — it has two):
1. `git clone --depth 1 --branch "$VERSION"` (ops/create-new-statbus-installation.sh:268, install.sh:358): a single-branch clone at a TAG writes exactly one fetch refspec — the tag pin — and never the wildcard. Every box born this way starts with the narrow refspec gh exhibited.
2. `git remote set-branches --add origin db-seed` (install.sh:339 and :365): unguarded append, one new identical config line per rescue/upgrade run. The comment at install.sh:337 CLAIMS "--add is idempotent" — empirically false (gh's three lines); the comment must die with the bug (verify-premises class).

THE CODEBASE ALREADY KNOWS BETTER: cli/cmd/install.go:1049-1064 does read-then-add (guarded); cli/internal/upgrade/refspec.go's CleanStaleRefspecs removes stale entries. The fix generalizes them: NORMALIZE-TO-CANONICAL — one function that makes remote.origin.fetch exactly {+refs/heads/*:refs/remotes/origin/*, +refs/heads/db-seed:refs/remotes/origin/db-seed} (dedupe, drop tag-pins and strays), invoked from ./sb install's step-table (idempotent; the product owns this config, so enforcement is derivation, not self-heal — same doctrine as the .env tier) — plus fixing the two shell writers: keep the cheap shallow clone if desired but normalize immediately after; guard or remove the set-branches --add calls (the Go normalizer may make them redundant — prefer deletion over guarding if so, clean break).

TESTS: unit tests on the normalizer (narrow-clone state → canonical; tripled state → canonical; already-canonical → no-op); the 291-genre source scan if a structural pin fits.

CONTEXT: today's fleet convergence hand-repaired gh (and previously five slots) — those repairs were the symptom treatment; this is the cause. Assigned: engineer (already holds install.sh for STATBUS-323 — same territory, one hand).

WHAT IS ACHIEVED: no box can be born with a broken refspec or accumulate one, and the next Ghana needs no repair because there is nothing to repair.
<!-- SECTION:DESCRIPTION:END -->
