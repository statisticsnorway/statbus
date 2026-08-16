---
id: STATBUS-207
title: >-
  test-install-stage0-red: Stage 0 HTTPS-sources verify fails on current Hetzner
  image at v2026.08.0-rc.01 — now a stable gate, blocks promotion
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-16 20:38'
updated_date: '2026-08-16 20:53'
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

author: mechanic
created: 2026-08-16 20:53
---
TRACE FINDINGS pt.1/2, comment #2's question (a) — via `gh run view 31970534511 --log`, the actual run's raw log, plus an isolated stub-based dry-run harness (real vm-bootstrap.sh sourced with faked ssh/scp/hcloud) to test bash control flow without provisioning a VM.

THE STATED PREMISE IS FALSE — there was no hardening failure to be swallowed. Exhaustive grep of the full run log for "HARDENING FAILED" (case-insensitive) returns ZERO matches. Decisively: the log contains the LITERAL line `VM statbus-recovery-0-happy-install bootstrap complete.` at 20:33:49.2147608Z — vm-bootstrap.sh:549, printed only AFTER `_apply_hardening` returns. So `_apply_hardening` genuinely returned 0 (success), not 1.

ROOT CAUSE of why it returned 0 despite Stage 0's verify printing ✗: ops/setup-ubuntu-lts-24.sh has NO mechanism anywhere that aggregates verify() failures into the script's own process exit code. Read main() end-to-end (lines 1155-1258): it calls all 8 stages as bare sequential statements (`stage_https_sources; stage_base_system; ...`), none of their return values are checked, and the script has only `set -o pipefail` at its top (line 17) — no `set -e`. verify() (line 70) itself just prints ✓/✗ and returns 0/1 to ITS OWN caller (the stage function), but nothing upstream inspects that. main()'s actual final statement is `if [[ -f /var/run/reboot-required ]]; then log_warn ...; fi` (line 1253), success regardless of branch taken. So setup.sh's exit code is effectively ALWAYS 0, independent of any verify() failure in any of its 8 stages — confirmed by the log itself: right after the ✗, `✓ APT update succeeds` appears (apt-get update -qq succeeded against whatever URIs are actually there), and all 7 remaining stages ran to completion normally.

I independently verified the OTHER half — that errexit DOES correctly propagate through vm-bootstrap.sh's bare-statement/sourced-function chain WHEN _apply_hardening genuinely returns non-zero — via a stub harness (stub ssh/scp/hcloud, forced harden_exit="1"): bootstrap_install_test_vm correctly stopped immediately, the scenario's EXIT trap fired, install_statbus_in_vm was never reached. So there is no errexit-suppression bug in vm-bootstrap.sh's control flow itself — the mechanism works; it was never triggered because setup.sh never signals stage-level failure to its caller AT ALL, for any of its 8 stages, not just Stage 0.
---

author: mechanic
created: 2026-08-16 20:53
---
TRACE FINDINGS pt.2/2, comment #2's question (b), plus one adjacent gap found.

(b) ANSWERED with direct log evidence. At 20:33:49.6907983Z, immediately after "bootstrap complete" (< 0.5s later), the raw log contains: `hcloud: Server not found: statbus-recovery-0-happy-install` — hcloud's own stderr, printed unredirected, right before the two ERR-trap lines at vm-bootstrap.sh:618 (the trap fires twice for that one line: once for the inner command substitution's own subshell context, once for the outer assignment — both `set -E`-propagated, same root failure). So hcloud's real reason IS already reaching the raw workflow log today — it's just not surfaced AS PART OF the harness's own diagnostic (the "✗ harness failure: rc=1 at ..." trap text doesn't include it), so a reader looking only at the harness-failure lines (or a truncated/filtered view) would miss it.

The mystery of WHY hcloud reported "Server not found": the SAME call (`hcloud server ip "$vm_name"`) succeeded for this exact VM name at 20:27:31.2260411Z (VM_IP=95.217.222.186), immediately after `hcloud server create`. The VM was then actively used for 6+ minutes — SSH reachable throughout (cloud-init wait, hardening via detached tmux, statbus user creation, SSH key fetch all succeeded per the log) — before hcloud's control-plane API reported it not found at 20:33:49, a 6m18s gap. No concurrent process or premature cleanup is visible in the log (the harness's own "Deleting VM" line fires AFTER this failure, as the EXIT trap's cleanup_vm). I cannot determine from logs alone whether this is a genuine Hetzner API-side transient/eventual-consistency issue or something else — flagging honestly as unresolved, not fabricating a cause. Given the architect's ruling scopes the ask to DIAGNOSABILITY (not root-causing Hetzner's side), implementing that: wrap the bare `hcloud server ip` call sites so a failure's diagnostic explicitly includes hcloud's own stderr, rather than relying on it being incidentally visible elsewhere in an unfiltered raw log.

ADJACENT GAP FOUND, not asked for, flagging rather than silently fixing or silently ignoring (per 'never defer known bugs'): the verify()-failures-never-propagate defect in setup-ubuntu-lts-24.sh is NOT Stage-0-specific — true for all 8 stages. Fixing ONLY Stage 0's verify semantics (ruling point 1) makes Stage 0's check goal-accurate, but even a redefined, goal-accurate Stage 0 verify failing would STILL not stop the script or signal the harness — the same silent-success shape persists for Stage 0 and stays latent for stages 1-8. Broader than the ticket's stated scope (Stage 0 rewrite + harness diagnosability). NOT touching main()'s stage-orchestration/exit-code aggregation as part of this build — cross-stage behavioral change beyond the two files' named scope in the dispatch; deserves an explicit call: fix now (small, scoped: fail the script if ANY verify() call failed, checked once at the very end of main()) or file separately. Proceeding with the ruled scope (Stage 0 rewrite + verify redefinition + hcloud diagnosability); noting this explicitly in my freeze report to the foreman for a decision, not deciding it myself.
---
<!-- COMMENTS:END -->
