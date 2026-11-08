---
id: STATBUS-595
title: Demo checkpoint publication is atomic with its lineage metadata
status: In Progress
assignee: []
created_date: '2026-11-08T11:59:00Z'
updated_date: '2026-11-08T12:28:00Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 511204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RC01 recovery job128722552493/run42477260886 refused its demo checkpoint before creating a scenario guest. First comparison read a missing or stale demo_parent, while the second read printed the correct parent. Current builder creates checkpoint before publishing demo_parent and candidate provenance, exposing a ready snapshot before its required identity is committed. Investigate and fix publication/readiness without weakening lineage rejection or disrupting the running battery.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A deterministic behavioral regression exposes concurrent readers between snapshot creation and lineage publication, fails before the fix and succeeds after it.
- [ ] #2 Readers reuse only fully published matching demo checkpoints, reject genuinely mismatched lineage, and handle incomplete builders using existing bounded ownership/reclaim rules.
- [ ] #3 Relevant checkpoint, snapshot-layer and harness regressions pass with first-attempt failure evidence preserved.
- [ ] #4 The corrected harness runs the failed arc and full candidate recovery gates in real guests before candidate acceptance.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
First-attempt log: tmp/combined-591-594-after-commit-first-failure.log. Failure occurred before scenario guest creation, not in injected migration recovery. Observe battery freeze: do not land scenario or harness changes while current battery is active.

2026-11-08 12:12 UTC root independently reproduced same-source deterministic regression RED=1 and prototype GREEN=0, including matching publication reuse, snapshot/fork identity, genuine parent/candidate mismatch refusals and interruption at all four metadata writes plus snapshot, with live/dead builder ownership recovery preserved. tmp/595/root-red-green-status.log and root-{red,green}.log. Minimal prepared patch moves the readiness checkpoint after metadata. git apply --check passes. Eight existing shell suites pass in both unchanged/patched copies. Tracked harness remains untouched while current real battery runs. New regression must be explicitly registered in Harness Selftest when landed. Real corrected guest acceptance remains open. Latest owner Norway halt does not halt normal595test hygiene.

2026-11-08 12:28 UTC: Git history independently locates the snapshot-before-metadata ordering in Oct20 commit5f96870f70 and the same bytes in accepted RC04/929fe787. This is a newly exposed pre-existing harness race, not evidence that591introduced a recovery defect. Earlier green runs do not establish this publication interleaving; which prior jobs reused a completed snapshot versus arrived later has not been established. New deterministic regression forces the reader at readiness publication and validates frozen snapshot/fork provenance. Separate tmp/595/ci-registration.patch adds it to the explicit Harness Selftest list, apply-check verified without changing tracked harness. Real current battery remains active with the single preserved first failure, no blind rerun. All four acceptance criteria remain open pending landed/final verification and real corrected guest gates.
<!-- SECTION:NOTES:END -->
