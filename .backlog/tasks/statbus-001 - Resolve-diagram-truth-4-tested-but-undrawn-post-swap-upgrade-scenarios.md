---
id: STATBUS-001
title: 'Resolve diagram-truth: 4 tested-but-undrawn post-swap upgrade scenarios'
status: To Do
assignee: []
created_date: '2026-06-07 11:24'
labels:
  - install-recovery
  - diagrams
  - upgrade
dependencies: []
references:
  - test/install-recovery/scenarios/3-postswap-archivebackup-resume.sh
  - test/install-recovery/scenarios/3-postswap-between-migrations-kill.sh
  - test/install-recovery/scenarios/3-postswap-migrate-killed-after-commit.sh
  - tmp/agents/mechanic-transcript-recovery.md
documentation:
  - doc/diagrams/upgrade-timeline.plantuml
  - doc/diagrams/install-recovery.plantuml
  - doc/recovery/recovery-injection-scope-a-comprehensive.md
  - tmp/RECOVERY-HANDOFF-2026-06-06.md
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The upgrade/install diagrams are the single source of truth for which upgrade interactions we test: every tested failure-injection scenario must correspond to an interaction drawn in the diagram. Four post-swap scenarios currently have a test but NO diagram TEST note, so the diagram and the test suite disagree. Resolve EACH scenario against this dichotomy:
- If the scenario is a logically-possible interaction → the diagram is incomplete → its TEST note must be added at the correct interaction point (a diagram regression to fix).
- If the scenario is logically impossible or redundant (already covered by an existing drawn interaction, or a duplicate kill-point) → the test is wrong → argue why and recommend retiring/merging it.

The four scenarios: 3-postswap-archivebackup-resume, 3-postswap-between-migrations-kill, 3-postswap-migrate-killed-after-commit, 3-postswap-watchdog-reconnect.

Crux to verify adversarially — the migrate-loop kill-points: the diagram already draws 3-postswap-mid-migration-kill (kill at top of runPsqlFile, before psql). Are between-migrations-kill (after migration N's db.migration INSERT, before N+1's runPsqlFile) and migrate-killed-after-commit (committed migration, db.migration row missing — the ~ms window) genuinely DISTINCT interaction points, or do they collapse into mid-migration-kill / each other? watchdog-reconnect targets the waitForDBHealth+reconnect step (already referenced in the timeline — likely just needs a note); archivebackup-resume targets archiveBackup on the exit-42 RESUME path (the resume path is drawn — is the resume-path archiveBackup a distinct point from the active-phase archiveBackup?).

ORDERING CONSTRAINT: the read-only ANALYSIS (verdict per scenario) can be done anytime. The actual diagram EDITS must land as a SEPARATE follow-up commit AFTER the install-recovery scenario-slug rename sweep (42 held working-tree files) is committed, to avoid concurrent diagram edits.

Context: recovered from the prior crashed session (harness task #46). This was the exact in-flight action when the session crashed mid-compaction. Full background in the recovery handoff doc.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each of the 4 scenarios has a written verdict: POSSIBLE→ADD (with exact diagram file + anchor line + proposed TEST-note text + the invariant it proves) or IMPOSSIBLE/REDUNDANT→RETIRE (with the argument)
- [ ] #2 The two migrate-loop kill-points (between-migrations-kill, migrate-killed-after-commit) are explicitly determined to be distinct interaction points OR collapsing into mid-migration-kill/each other, with reasoning
- [ ] #3 For every POSSIBLE verdict: the diagram TEST note is added at the correct interaction point in the right phase, consistent with surrounding flow, as a follow-up commit landing AFTER the rename sweep is committed
- [ ] #4 For every RETIRE verdict: the scenario test and its README catalogue entry are removed or merged, with rationale recorded
- [ ] #5 Both diagrams re-rendered to SVG after any edit, and the diagram once again matches the tested scenario set exactly
<!-- AC:END -->
