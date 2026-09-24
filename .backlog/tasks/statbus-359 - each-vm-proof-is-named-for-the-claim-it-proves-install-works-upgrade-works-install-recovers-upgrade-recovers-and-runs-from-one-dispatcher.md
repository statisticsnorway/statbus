---
id: STATBUS-359
title: One dispatcher runs four VM proof families named for their outcomes
status: To Do
assignee: []
created_date: '2026-09-07 07:56'
updated_date: '2026-09-24 18:47'
labels:
  - harness
  - release
  - naming
dependencies:
  - STATBUS-362
ordinal: 80
---

## Description

The paid VM proofs live under `test/vm/` in four positive outcome families: `install-works`, `upgrade-works`, `install-recovers`, and `upgrade-recovers`. One `test/vm/run.sh` dispatches by family, name, or all. The development entry point is `./dev.sh test-vm <family|name|all>`, while the free local Multipass check is `./dev.sh test-install-local`.

## Dated inventory, 2026-09-24

A repository inventory in this worktree found 16 `test/install-recovery/scenarios/*.sh` files and 35 `test/install-recovery/arcs/*-arc.sh` files. Those are source-file counts, not final family counts. The earlier 15, 33, and 98 counts and historical CI descriptions are withdrawn. The authoritative family counts are generated after classification by the named dispatcher contract test below.

Current dispatch and release-gate entry points are `test/install-recovery/run.sh` and `cli/cmd/release/release.go:1463,1945,1972` at master `7a9cf707e`.

## Acceptance Criteria

- [ ] #1 `new: test/vm/tests/dispatcher-contract-test.sh` enumerates every moved proof exactly once in one of the four families and prints the computed count for each family.
- [ ] #2 `new: test/vm/tests/dispatcher-contract-test.sh` proves `test/vm/run.sh --list`, `--print-selected`, family selection, name selection, and all selection use one dispatch contract.
- [ ] #3 `new: test/vm/tests/dev-command-contract-test.sh` proves `./dev.sh test-vm` dispatches paid proofs and `./dev.sh test-install-local` retains the free local check.
- [ ] #4 `new: test/vm/tests/release-contract-test.sh` proves coverage homes, release gates, workflow matrices, orchestrator job IDs, and release-ladder labels use the four positive family names.
- [ ] #5 `new: test/vm/tests/family-vocabulary-test.sh` lists every remaining historical vocabulary hit with its non-family reason and positively verifies every active proof and operator command uses one of the four target family names.
- [ ] #6 `new: test/vm/run.sh all` paid scenario `STATBUS-359-four-cell-ladder-1`, selected and checked by `new: test/vm/tests/release-contract-test.sh`, runs the first candidate tag after landing and verifies `new: test/vm/evidence/STATBUS-359-four-cell-ladder-1.md` records all four families green through the release-candidate ladder.
