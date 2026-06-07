---
id: STATBUS-006
title: Fix stale NN scenario references in install-recovery CI workflows
status: In Progress
assignee:
  - mechanic
created_date: '2026-06-07 15:15'
labels:
  - install-recovery
  - rename
  - ci
dependencies: []
references:
  - .github/workflows/install-recovery-harness.yaml
  - .github/workflows/test-install.yaml
priority: medium
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The scenario rename (NN-slug -> <phase>-<slug>, e.g. 21-preswap-backup-kill -> 2-preswap-backup-kill) missed the .github/workflows/ files — another corner like dev.sh + release-workflow-gates.md (fixed under STATBUS-003). install-recovery-harness.yaml still uses old NN names in its `scenarios` workflow_dispatch input example ("01 09 23", "08 12") and inline comments (scenarios/NN-*.sh, statbus-recovery-NN, install-recovery-NN.log). The mechanism works with slugs (run.sh discovers scenarios/*.sh), but operators dispatching the workflow see stale examples.

Sweep ALL .github/workflows/*.yaml for surviving old NN scenario refs and update to canonical slugs. Comments/examples/strings only — NO behavioral change. Watch for false positives (e.g. "rc.67-migration" is a release ref, not a scenario).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All .github/workflows/*.yaml swept; no surviving old NN scenario refs (NN-prefix scenario names, scenarios/NN-*.sh, statbus-recovery-NN, install-recovery-NN.log) — verified by grep
- [ ] #2 install-recovery-harness.yaml `scenarios` workflow_dispatch input example + inline comments use canonical slugs
- [ ] #3 No behavioral change to any workflow — comment/example/string updates only
<!-- AC:END -->
