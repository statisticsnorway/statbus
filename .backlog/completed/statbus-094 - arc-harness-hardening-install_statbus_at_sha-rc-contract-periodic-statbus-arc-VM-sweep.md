---
id: STATBUS-094
title: >-
  arc-harness-hardening: install_statbus_at_sha rc-contract + periodic
  statbus-arc VM sweep
status: Done
assignee: []
created_date: '2026-06-18 18:14'
updated_date: '2026-07-06 15:59'
labels:
  - upgrade
  - test-harness
  - phase-2-followon
  - hardening
dependencies: []
priority: low
ordinal: 94000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two non-blocking follow-ups flagged by the architect during the STATBUS-071 arc (c) review (commit c30595393). Both are hardening, not correctness-blockers — addressed in the 071 hardening pass (after the framework's arcs are green).

1. rc-CONTRACT ALIGNMENT: test/install-recovery/arcs/working-arc.sh runs install_statbus_at_sha under `set -e`, which aborts on ANY non-zero — slightly inconsistent with the helper's own comment ("callers decide from row state"). Harmless for A (a fresh install lands rc=0, never the rc=75 upgrade-rollback exit), but align for contract-consistency: either mask rc=75->0 inside install_statbus_at_sha, OR have the caller tolerate it explicitly.

2. PERIODIC statbus-arc-* VM SWEEP (€-safety backstop): the arc's `trap cleanup_vm` + the run-arc if:always() net reaper cover normal/error/cancel, but a runner hard-kill mid-always-teardown could leave an orphan Hetzner VM (€). install-recovery has a periodic sweep but it only matches `statbus-recovery-*`; add an equivalent periodic sweep for the disjoint `statbus-arc-*` prefix (or generalize the existing sweep to both prefixes).

Source: doc-012 / the arc (c) architect review. Low priority; framework correctness is unaffected.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
MERGED into STATBUS-071: two small arc-harness-hardening items for 071's hardening residual list (094's own text already said "addressed in the 071 hardening pass").
<!-- SECTION:FINAL_SUMMARY:END -->
