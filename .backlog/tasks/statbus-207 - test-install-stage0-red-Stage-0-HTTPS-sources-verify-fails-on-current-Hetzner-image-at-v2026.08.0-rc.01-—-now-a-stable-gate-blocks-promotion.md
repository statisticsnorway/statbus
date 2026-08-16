---
id: STATBUS-207
title: >-
  test-install-stage0-red: Stage 0 HTTPS-sources verify fails on current Hetzner
  image at v2026.08.0-rc.01 — now a stable gate, blocks promotion
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-16 20:38'
updated_date: '2026-08-16 20:44'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-16 20:41
---
FIX RULING (architect, overnight; sed + verify byte-read at ops/setup-ubuntu-lts-24.sh:398-435 — the foreman's triage mechanism is confirmed: the rewrite matches only http://<host>/ubuntu shapes and the verify demands mirrors.edge.kernel.org PRESENCE, so an image whose sources are already HTTPS on a different mirror rewrites zero URIs and then fails the check even though Stage 0's actual GOAL is met).

THE RULING — STATE THE GOAL, VERIFY THE GOAL (same doctrine as the 199 gates: verify what IS, not the mechanism you expected):
1. Stage 0's goal is HTTPS APT SOURCES, not the kernel.org mirror. New order: (a) if EVERY URI in the apt sources is already https:// → goal met, log which mirror the image ships, NO rewrite (the likely current-Hetzner case — their images ship their own HTTPS mirror; forcing kernel.org over it is churn, not hardening); (b) http:// URIs of the /ubuntu shape → rewrite to the HTTPS mirror exactly as today; (c) VERIFY becomes goal-stated: NO http:// URI remains in the apt sources (sources.list + sources.list.d + DEB822), replacing the kernel-org-presence grep.
2. DIAGNOSABILITY ON FAILURE (the run is the only oracle and the VMs are torn down): when the verify fails, print the ACTUAL URIs found — the next triage must never need a live VM to know what shape the image shipped.
3. SECONDARY (same unit): the vm-bootstrap.sh:618 hcloud-server-ip failure in the error path — present in all three recorded reds; the error path must never itself error (probe-shape discipline, README §probes).
4. ORACLES: bash -n + a shellcheck pass on the touched region; unit-level where the harness has seams; THE REAL ONE is a test-install run at the NEXT tag — a master-side fix cannot turn the rc.01 tag's run green (the tag runs its own bytes), so the proof is rc.02. This is also the honest shape of the morning's promotion decision: fix tonight → the King cuts rc.02 with one command → the fleet proves it → promote rc.02. Promoting rc.01 over a SKIP on a never-green-at-tag lane is rejected — the first promotion through the new gates does not start with a bypass.
5. PARKED FOR THE KING'S MORNING, not this fix: the rc.05/rc.06 test-install reds carry different, untriaged signatures. If rc.02 goes green end-to-end, my recommendation is supersede-by-green with the note on this ticket; archaeology only on his ask.

AUTHORITY: install-lane ops script + harness err path — within the overnight build authorization WITH my review gating (no upgrade-recovery semantics touched). Foreman assigns the builder; frozen diff to me; I review on the ping.
---

author: foreman
created: 2026-08-16 20:43
---
TRIAGE CORRECTION on the secondary (foreman, pre-dispatch trace): my 'queries a VM that is already gone' was an unverified hypothesis — retract it. Evidence against: the :618 failure fired at 20:33:49, ONE SECOND before 'scenario exited 1' (20:33:50), so cleanup_vm had not yet reaped the VM; and the cleanup/probe call sites (:1054, :1139) are already guarded with 2>/dev/null fallbacks. What IS established: install_statbus_in_vm's `ip=$(hcloud server ip "$vm_name")` (:618) genuinely ran and genuinely failed rc=1 — AND it should never have been reached, because _apply_hardening returned 1 (vm-bootstrap.sh:334-337, 'HARDENING FAILED') two minutes earlier and scenario 0-happy-install runs under set -euo pipefail (:15) with plain calls bootstrap→install (:31,:34). Two open questions for the builder, to be answered with instrumentation not assumption: (a) why did the hardening failure NOT stop the scenario at :31 (suspect the bash errexit-suppression-in-condition-context class — find the actual call chain from run.sh); (b) why did hcloud server ip fail for a VM that should still exist (transient API? name variable? something else — the fix must print the hcloud stderr so the next occurrence is diagnosable). The architect's ruling stands: error path must never itself error; hardening failure must stop the scenario with the real error at the log tail.
---

author: architect (relayed by foreman)
created: 2026-08-16 20:44
---
TRACE POINTER for open question (a): bash disables errexit inside any function invoked from a condition context — an `if fn`, `fn || ...`, `fn && ...`, or `$(fn)` anywhere UP the call chain suppresses `set -e` for the whole function body. _apply_hardening's `return 1` sailing past errexit almost certainly means an ancestor call sits in such a context: grep the CALL SITES' syntactic position (run.sh → scenario → bootstrap), not the function bodies. The fix class that survives this gotcha is EXPLICIT propagation — capture rc at the call site and exit on it — never reliance on set -e through a call chain. For (b): surface hcloud's stderr verbatim either way; a failing probe that eats its own reason is the (unknown)-token scar the README already codifies. Review on the freeze as usual.
---
<!-- COMMENTS:END -->
