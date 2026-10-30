---
id: STATBUS-325
title: >-
  refspec-birth-defects: the single-branch clone writes a tag-pinned refspec
  with no wildcard, and set-branches --add duplicates forever — normalize to
  canonical, in code
status: Done
assignee:
  - engineer
created_date: '2026-08-31 11:35'
updated_date: '2026-08-31 11:57'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LANDED at 71ca22be5. Both birth defects dead at source: the single-branch clone's narrow refspec is normalized immediately after cloning, and both shell set-branches --add calls are DELETED along with the false-idempotence comment (named in the commit as the reason nobody looked; empirically refuted — three runs, three identical lines, reproduced in a scratch origin before building). One normalizer replaces the surgical cleaner: --unset-all + write the canonical pair, exact by construction, idempotent unguarded — replacing a mechanism that structurally could not clean its own target input (git config --unset refuses on multiple matches, gh's exact tripled state). Two designed call sites per the architect's confirmed reconciliation: install (inside the already-held step-table mutex) and apply-latest's pre-step (verified OUTSIDE any protected region, so it takes 323's install-held flag; contention = skip-and-say-so, never a failed upgrade). The DECLARATION is doc-commented and test-pinned: remote.origin.fetch is product-owned derived config, rewritten canonically on every install and upgrade, hand edits do not survive — the sentence separating derivation from silent self-heal. Old cleaner's real job (stale devops/* removal) covered and tested. Two self-caught test failures recorded: the testgit-package guard caught a raw-git helper (harness-is-its-own-environment), and a case-sensitive assertion against the author's own banner. The next Ghana is born canonical and stays canonical.
<!-- SECTION:FINAL_SUMMARY:END -->
