---
id: STATBUS-003
title: Review the install-recovery scenario-slug rename for consistency + correctness
status: In Progress
assignee: []
created_date: '2026-06-07 11:25'
updated_date: '2026-06-07 11:46'
labels:
  - install-recovery
  - rename
  - review
dependencies: []
references:
  - test/install-recovery/scenarios/
  - test/install-recovery/README.md
  - test/install-recovery/run.sh
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The install-recovery scenarios were renamed from NN-slug to <phase>-<slug> (phases: 0/1-boot/2-preswap/3-postswap/4-rollback/5-install). The file renames are committed; the content-canonicalization sweep (~42 working-tree files: README, run.sh, in-file headers, diagrams, a few cli/ comments) is held UNCOMMITTED pending this review. The review was dispatched in the prior session but never reported before the crash, so re-run it. Once it (and the corner-audit + grip-map) pass, the held sweep gets committed.

Recovered from harness task #42.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No surviving old scenario identifier (NN-prefix, old slug, statbus-recovery-NN) anywhere it matters, verified by grep
- [ ] #2 5 representative slugs each resolve across filename, runner, README, diagram, and in-file header
- [ ] #3 Verdict reported: APPROVE, or a defect list with file:line
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Review verdict (2026-06-07): NOT clean — defects found.

(1) FUNCTIONAL BUG (fixed this session): dev.sh referenced scenarios/01-happy-install.sh (renamed to 0-happy-install.sh) — `./dev.sh test-install` was broken. Also stale 'scenario 01' text at dev.sh:1989, 2006, 2019. dev.sh was a MISSED CORNER: untouched by the rename sweep, and outside STATBUS-004's test/install-recovery/ scope. Fix lives in the working tree, to commit with the held sweep.

(2) DOC REFS (scope decision pending): doc/release-workflow-gates.md:43-44 say 'scenario 01' (active operational doc). doc/recovery/*.md carry many 'scenario NN' numeric refs (18/19/21/22/26/27…) in historical design/forensic narratives. Decide: update active docs to slugs vs keep historical record as-is.

AC#2: 5 representative slugs resolve across file + README + diagram. run.sh names only special-cased scenarios and auto-discovers the rest — not a defect.
<!-- SECTION:NOTES:END -->
