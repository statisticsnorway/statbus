---
id: STATBUS-356
title: >-
  test slot has two contradictory contracts: active channel-following installation and destructive CI executor; choose one and enforce it
status: To Do
assignee: []
created_date: '2026-09-04 19:52'
updated_date: '2026-09-25 12:20'
labels:
  - owner-decision
  - ops
  - upgrade
  - ci
  - fail-fast
dependencies: []
references:
  - doc/CLOUD.md
  - cloud.sh
  - ops/niue/sshdoers
  - .backlog/completed/statbus-254 - fleet-channel-correction-production-boxes-are-being-offered-release-candidates-today-and-no-amount-of-reinstalling-will-fix-it.md
priority: high
type: bug
ordinal: 349000
---

## Status 2026-09-24

**To Do, owner decision:** neither serving-installation nor disposable-CI role has been selected, and no role-regression test or tag cleanup is merged. **Remaining:** declare one authoritative role, isolate the opposite machinery, reconcile conflicting refs, and prove healthy observable service/CI state.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## The contradiction

The niue `test` slot currently has two incompatible declared roles:

1. `doc/CLOUD.md` lists `test.statbus.org` among the active installations. STATBUS-254 explicitly repaired its missing upgrade unit and closed only after the running service logged `channel=stable`.
2. `cloud.sh` deliberately excludes `statbus_test` from the operated fleet, while `ops/niue/sshdoers` gives it a dedicated `./dev.sh continous-integration-test` entry. That workload can stop, replace, or recreate database state and cannot safely coexist with a promise that this is an ordinary serving installation.

Observed again during STATBUS-248 post-verification on 2026-09-04:

- no StatBus containers are running for the slot;
- `statbus-upgrade@statbus_test.service` has been failed since 2026-08-27 20:07 UTC;
- the installed user unit differs from the shipped template;
- the generated channel is `stable`, but there is no running service from which to verify it;
- `./sb upgrade list` fails because the database is stopped;
- `git fetch --tags --prune-tags --dry-run` refuses to clobber two historical tags:
  - local `v2026.03.0-rc.43=f3a7f117...`, origin `469133689...`;
  - local `v2026.03.0-rc.47=51ea48e0...`, origin `dfd223494...`.

The tag mismatch is old rebaseline residue. It is not related to deploy-refspec retirement and did not block STATBUS-248.

## Decision required before repair

Choose one role. Do not preserve the current half-state.

### A. Serving installation

If `test.statbus.org` is meant to be an ordinary active installation, add it to the authoritative fleet operations and health story, remove or isolate the destructive CI use, repair it through `./sb install`, and prove containers, database, upgrade service, channel, ledger, and release fetch all remain healthy.

### B. CI executor

If it is dedicated disposable CI infrastructure, remove it from the active-installation inventory, make the quiescent service/container state explicit rather than failed, and ensure CI setup owns checkout/tag cleanup deterministically before every run.

## Done when

- One role is declared in one authoritative registry and every document/tool agrees with it.
- The opposite role's machinery is removed or isolated so the slot cannot silently alternate contracts.
- `git fetch --tags --prune-tags --dry-run` succeeds without force-clobber ambiguity; the two conflicting tags are diagnosed and corrected deliberately, not hidden.
- Service/container/database state is correct for the chosen role and observable as such. A failed unit is never the steady state.
- A regression check fails if the contradictory role returns.
## Grounded facts, 2026-09-25

The destructive CI executor side of this contract is `.github/workflows/pg_regress.yaml` job `pg_regress_trusted` on `runs-on: [self-hosted, niue]`, triggered by workflow_run after Images on every master push. It SSHes to niue as `statbus_test` and runs `./dev.sh continous-integration-test`, which does `./dev.sh delete-db`, `./dev.sh create-db`, then `./dev.sh migrate-and-test fast` (dev.sh:1228-1316). That is the SAME suite `.github/workflows/fast-tests.yaml` runs on a GitHub-hosted runner. The release preflight gates only on fast-tests.yaml (cli/cmd/release/release.go:176); pg_regress gates nothing. Measured today: pg_regress 45-85 min per run (10:03->10:48, 08:28->09:52) vs Fast Tests 15-30 min. It also occupies the only niue self-hosted runner: rc.05's dev-canary deploy (run 36126656902, `runs-on: [self-hosted, niue]`) queued from 10:56 behind pg_regress run 36125263046 (started 10:48). Proposal awaiting owner decision: remove pg_regress's automatic triggers (workflow_run and pull_request), keep workflow_dispatch as the manual fallback its name says it is; this resolves the destructive-executor half of this ticket.

<!-- SECTION:DESCRIPTION:END -->

## Reconciliation 2026-09-23

Classification: OPEN. Evidence: test slot contradictory role and failed service remain recorded, with no repair commit. No part of the item's own done-when is complete beyond any design already recorded above.
