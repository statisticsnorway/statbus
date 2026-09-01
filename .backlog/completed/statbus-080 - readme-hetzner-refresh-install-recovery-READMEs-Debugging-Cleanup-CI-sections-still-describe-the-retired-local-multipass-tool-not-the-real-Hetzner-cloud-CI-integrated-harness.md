---
id: STATBUS-080
title: >-
  readme-hetzner-refresh: install-recovery README's Debugging/Cleanup/CI
  sections still describe the retired local-multipass tool, not the real
  Hetzner-cloud + CI-integrated harness
status: Done
assignee:
  - '@operator'
created_date: '2026-06-17 20:37'
updated_date: '2026-06-17 20:45'
labels:
  - docs
  - install-recovery
  - clarity
  - follow-up
dependencies:
  - STATBUS-070
references:
  - test/install-recovery/README.md
  - test/install-recovery/lib/vm-bootstrap.sh
  - .github/workflows/install-recovery-harness.yaml
priority: medium
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT: update the install-recovery README's tail sections (Debugging, Cleanup, CI integration) to match how the harness actually works today.

WHY: those three sections are stale — they describe `multipass` (a retired local-VM tool) and claim the harness is "Not currently integrated" in CI. Both are false now (confirmed 2026-06-17): `multipass` appears ONLY in the README; the harness provisions Hetzner Cloud VMs via hcloud (test/install-recovery/lib/vm-bootstrap.sh, data-helpers.sh, assertions.sh, run.sh), and it IS CI-integrated via .github/workflows/install-recovery-harness.yaml (runs the full 32-scenario matrix on Hetzner, tag-push + manual dispatch). A developer following the README's debug/cleanup steps would run commands that don't apply.

SCOPE:
1. Debugging — replace the `multipass shell/exec` steps with the Hetzner --keep-vm flow (ssh/hcloud into the kept VM).
2. Cleanup — replace `multipass list/delete/purge` with the hcloud server cleanup.
3. CI integration — rewrite "Not currently integrated… Multipass requires nested virtualization" (false) to describe the real install-recovery-harness.yaml integration.

OWNER: operator (owns the Hetzner harness lifecycle + knows the exact hcloud debug/cleanup commands). FOUND while finishing STATBUS-070's catalogue clarity pass (the catalogue itself is fixed in 5efe6dfe7). NON-cut-blocking — developer-facing doc accuracy.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DONE by foreman, committed + pushed 1662a1274 (2026-06-17). FIXED DIRECTLY rather than deferred to the operator — King's ruling: docs are part of the clean ship, nothing swept under the rug. The 3 stale README sections now describe the real flow: Debugging = `ssh root@$(hcloud server ip statbus-recovery-<slug>)` + the artifact download; Cleanup = `hcloud server list` / `hcloud server delete`; CI integration = the real install-recovery-harness.yaml (Hetzner matrix, tag-push + manual dispatch, per-commit images, release-preflight gate) replacing the false 'not currently integrated / Multipass needs nested virtualization'. Extracted the exact commands from lib/vm-bootstrap.sh (cleanup_vm + VM_EXEC + SSH_OPTS).
<!-- SECTION:NOTES:END -->
