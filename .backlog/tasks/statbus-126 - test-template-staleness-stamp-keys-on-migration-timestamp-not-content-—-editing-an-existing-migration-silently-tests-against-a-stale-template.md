---
id: STATBUS-126
title: >-
  test-template-staleness: stamp keys on migration timestamp, not content —
  editing an existing migration silently tests against a stale template
status: To Do
assignee: []
created_date: '2026-07-02 19:34'
labels:
  - testing
  - infra
  - dev-tooling
dependencies: []
ordinal: 127000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: editing a migration's content can never silently test against a stale template.
> BENEFIT: the false "fix didn't work" class is gone — content edits to an applied migration invalidate the template automatically (one diagnosis cycle was already lost to this; every future migration edit is exposed to it until fixed).
> STAGE: Testing foundation / dev tooling.
> COMPLEXITY: engineer-substantial (re-key the stamp on a content hash; the seed work's UpMigrationsFingerprintUpTo is the reuse candidate).
> DEPENDS ON: nothing.

---

Found live during the power-group substrate build (2026-07-02): the test-template staleness stamp (`tmp/test-template-migrations-sha`) records the max migration TIMESTAMP. Editing the CONTENT of an existing migration file therefore does NOT invalidate the template — `./dev.sh test` silently reuses the stale template and produces false results against the old schema.

Observed instance (conclusive): during STATBUS-124, the architect appended three timeline-object fixes to his already-applied migration (timestamp 20260702185257); the stamp still matched, run 2 reused the template built BEFORE the append, and test 120 reproduced the identical pre-fix diff — a false "fix didn't work" that cost a diagnosis cycle. The same hazard applies to any edit of an existing migration — e.g. the seed-drift fix (commit 8b5912a9a edited migration 20260218215337): any test run after such an edit without a forced template rebuild tests stale.

THE FIX: key the staleness stamp on a CONTENT HASH of migrations/ (e.g. hash of sorted filename+content digests — the `UpMigrationsFingerprintUpTo` machinery from the seed work already computes migration content fingerprints and may be reusable), not on the max timestamp. Then any byte change to any migration invalidates the template automatically.

WORKAROUND until fixed (for anyone editing an existing migration): remove `tmp/test-template-migrations-sha` and rebuild the template (`./dev.sh create-test-template` or the recreate-seed path) before trusting test results.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The template-staleness check invalidates on any CONTENT change to any migration file (not only on a newer timestamp) — demonstrated by editing an applied migration's bytes and observing the template rebuild trigger
- [ ] #2 No regression: an unchanged migrations/ directory still reuses the template (no rebuild-every-run)
- [ ] #3 The stamp mechanism documents what it keys on, in place
<!-- AC:END -->
