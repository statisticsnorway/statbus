---
id: STATBUS-207
title: >-
  test-install-stage0-red: Stage 0 HTTPS-sources verify fails on current Hetzner
  image at v2026.08.0-rc.01 — now a stable gate, blocks promotion
status: To Do
assignee: []
created_date: '2026-08-16 20:38'
labels:
  - release
  - quality-gate
  - install-recovery
dependencies: []
references:
  - ops/setup-ubuntu-lts-24.sh
  - test/install-recovery/lib/vm-bootstrap.sh
  - .github/workflows/test-install.yaml
priority: high
ordinal: 207000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: test-install is a stable-promotion gate since STATBUS-205 — a red run here blocks `./sb release stable` unless deliberately bypassed with SKIP_TEST_INSTALL=1. This red must be understood, not waved through.
> FOUND: overnight watch 2026-08-16, run 31970534511 (push of tag v2026.08.0-rc.01, commit 5d141d3ca). No-flaky triage below; NO fix dispatched overnight per standing orders — architect morning review decides the remedy.

PRIMARY (new signature at this RC): setup-ubuntu-lts-24.sh Stage 0 verify "HTTPS sources configured" fails on the VM. The log (20:31:42Z) shows the NOT-already-configured branch ran — "Backing up original sources... Switching to HTTPS mirror..." — yet the verify grep for mirrors.edge.kernel.org finds nothing afterwards. That means the sed at ops/setup-ubuntu-lts-24.sh:408 (`s|http://[^/]*/ubuntu|https://mirrors.edge.kernel.org/ubuntu|g`) matched ZERO URIs in the DEB822 ubuntu.sources: the current Hetzner Ubuntu 24.04 image's apt URIs no longer fit the `http://.../ubuntu` shape (plausibly already-HTTPS mirror.hetzner.com, or a changed URI path). The verify at :432 then hard-fails even though APT itself may be perfectly healthy. HYPOTHESIS to confirm on a VM (or by inspecting the image's ubuntu.sources) before any fix: dump the actual URIs.

SECONDARY (persistent wart, seen in ALL of the last three red runs incl. rc.05/rc.06 era): the failure path trips `✗ harness failure: rc=1 at vm-bootstrap.sh:618: ip=$(hcloud server ip "$vm_name")` (formerly :573) — the teardown/err path queries a VM that is already gone, garbling the real error at the tail of the log. Harness-only defect, never the scenario's cause, but it costs triage time every red run.

NOTE the prior-generation reds: rc.05 (29260999692) and rc.06 (29347383207) also failed but WITHOUT the Stage-0 signature — their visible failure is only the hcloud wart; their true causes were never triaged. The lane has not been green at an RC tag in the recorded history — worth stating plainly at the morning stable-promotion discussion.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Actual apt source URIs of the current Hetzner Ubuntu 24.04 image captured as evidence; Stage 0 fix (or deliberate verify redefinition) designed against them, architect-reviewed
- [ ] #2 vm-bootstrap.sh failure path no longer trips the hcloud server-ip harness failure after VM deletion — the real error reaches the log tail clean
- [ ] #3 test-install green at an RC tag observed (the stable gate passes without SKIP_TEST_INSTALL)
<!-- AC:END -->
