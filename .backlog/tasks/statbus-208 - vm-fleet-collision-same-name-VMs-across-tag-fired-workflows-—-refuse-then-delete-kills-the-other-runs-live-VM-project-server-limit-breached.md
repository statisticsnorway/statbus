---
id: STATBUS-208
title: >-
  vm-fleet-collision: same-name VMs across tag-fired workflows —
  refuse-then-delete kills the other run's live VM; project server limit
  breached
status: To Do
assignee: []
created_date: '2026-08-16 20:54'
labels:
  - install-recovery
  - quality-gate
  - release
dependencies: []
references:
  - test/install-recovery/lib/vm-bootstrap.sh
  - .github/workflows/install-recovery-harness.yaml
  - .github/workflows/test-install.yaml
  - .github/workflows/upgrade-arc-harness.yaml
priority: high
ordinal: 208000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: one tag push fires test-install, install-recovery-harness, and the arc harness into ONE Hetzner project; every run must get its VMs, keep them for its lifetime, and never touch another run's. Until that holds, the tag fleet destroys itself and no gate verdict is trustworthy.
> FOUND: overnight loop 2026-08-16, v2026.08.0-rc.01 fleet. Evidence chain from runs 31970534511 (test-install) and 31970534492 (install-recovery).

DEFECT A — CROSS-RUN NAME COLLISION + REFUSE-THEN-DELETE (killed test-install): both test-install.yaml and install-recovery-harness.yaml run a scenario named 0-happy-install; VM names are scenario-derived (statbus-recovery-0-happy-install) with NO run-unique component. Timeline: 20:27 test-install creates the VM. 20:28:12 the install-recovery run's 0-happy-install job hits the refuse-on-existing check (vm-bootstrap.sh ~:530) — CORRECT refusal, message names the foreign owner. 20:28:39 the SAME job's cleanup/reap path prints "Server statbus-recovery-0-happy-install deleted" — it deleted a VM it never created. test-install's harness, SSH-ing by cached IP, kept streaming plausible hardening output (the IP had been recycled to a sibling scenario VM running the identical hardening — silent cross-wire) until "bootstrap complete", then died at :618 with "hcloud: Server not found". Mechanic is landing the tactical guard tonight under STATBUS-207 (cleanup never deletes a VM the job did not create); the STRUCTURAL fix — run-scoped VM names, and/or removing the duplicate scenario from one workflow — needs an architect ruling.

DEFECT B — PROJECT SERVER LIMIT BREACHED (killed 13 more scenarios): 13 install-recovery scenario jobs died at create with "hcloud: server limit reached (resource_limit_exceeded)" (vm-bootstrap.sh:535, 20:36-20:39Z). Each harness is internally throttled (max-parallel: 3, install-recovery-harness.yaml:337; same in the arc workflow) but the throttles are PER-WORKFLOW — the tag push runs the workflows concurrently, so combined demand (install-recovery 3 + test-install 1 + arcs 3 when running) exceeds the project limit the per-workflow bound was sized against. Remedy options for the ruling: cross-workflow concurrency coordination (shared GH concurrency group or explicit sequencing), per-workflow max-parallel resized to a fleet budget, create-retry with backoff on resource_limit_exceeded, and/or a Hetzner project limit raise (account-level operator action — King/ops).

NOTE: the "Reap orphan VMs (final global sweep)" job succeeded in the same run — verify its ownership discipline too while ruling A (a global sweep that deletes by name-pattern has the same cross-run blast radius).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect ruling on the structural remedy: run-scoped VM naming and/or scenario dedup across workflows, and the cross-workflow capacity design (concurrency budget vs limit raise vs retry-backoff)
- [ ] #2 No VM is ever deleted by a run that did not create it — including the global orphan sweep's ownership discipline
- [ ] #3 A full tag-push fleet (test-install + install-recovery + arcs) completes with zero resource_limit_exceeded and zero cross-run interference — observed at an RC tag
<!-- AC:END -->
