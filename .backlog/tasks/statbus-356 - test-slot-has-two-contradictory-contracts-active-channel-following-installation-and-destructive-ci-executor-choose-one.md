---
id: STATBUS-356
title: >-
  test slot has two contradictory contracts: active channel-following installation and destructive CI executor; choose one and enforce it
status: To Do
assignee: []
created_date: '2026-09-04 19:52'
updated_date: '2026-09-04 19:52'
labels:
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
<!-- SECTION:DESCRIPTION:END -->
