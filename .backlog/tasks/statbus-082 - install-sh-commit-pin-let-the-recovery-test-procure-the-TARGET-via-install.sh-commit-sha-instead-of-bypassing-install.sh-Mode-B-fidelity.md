---
id: STATBUS-082
title: >-
  install-sh-commit-pin: let the recovery test procure the TARGET via install.sh
  --commit <sha> instead of bypassing install.sh (Mode B fidelity)
status: To Do
assignee: []
created_date: '2026-06-17 22:06'
updated_date: '2026-07-12 02:42'
labels:
  - install-recovery
  - fidelity
  - install-sh
  - follow-up
dependencies: []
references:
  - 'test/install-recovery/lib/vm-bootstrap.sh:489'
  - 'install.sh:164'
  - 'install.sh:177'
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the recovery test procures its target through the operator's real action — install.sh, pinned to an exact commit.
> BENEFIT: the harness stops bypassing the very script it exists to validate (the reuse-staged-binary gate), and the recurring master-moved-mid-run nondeterminism is gone — recovery runs test what an NSO operator actually executes, pinned.
> STAGE: Testing foundation (Mode B fidelity).
> COMPLEXITY: engineer-substantial (a --commit procurement path in install.sh + harness switch-over).
> DEPENDS ON: nothing.

---

WHAT: The install-recovery harness's recovery step (install_statbus_in_vm no-version branch, vm-bootstrap.sh:489-535) currently invokes `install.sh --channel edge`. That tracks the MOVING master tip, so if master advances during a run (it moved 11 commits in ~50min overnight) the recovery procures a drifted binary and the "binary unchanged after abort" assertions fail — a non-deterministic, master-move-dependent race. The rc.04 batch fixes this with Mode B option (b): an env-gate (SB_RECOVERY_REUSE_STAGED_BINARY=1) that makes recovery REUSE the already-staged target binary (~/statbus/sb from upload_sb_to_vm) instead of calling install.sh. That is deterministic and target-pinned, but it BYPASSES install.sh in the recovery path.

WHY (the King's value): install.sh is the operator's SOLE action — especially for a no-remote-access NSO box. The install-recovery harness exists to validate that the operator's install.sh recovery WORKS. Option (b) removes install.sh from the recovery test path, a real fidelity reduction. The fuller fix keeps install.sh in the loop while still being deterministic + target-pinned: teach install.sh a `--commit <sha>` procurement (today install.sh --version is v-TAG-only; a per-commit test has no tag, which is why edge was used). With `--commit <sha>`, the recovery test could run `install.sh --commit <target-sha>` — the real operator code path, pinned to the exact target, no master drift.

STATUS / NON-GATING for rc.04: option (b) unblocks the cut deterministically (the per-commit run inherently can't do tag-procurement — no tag exists pre-cut). This task restores the install.sh-in-the-loop fidelity afterward. Surfaced during the rc.04 install-recovery triage (run 27715901866, Mode B). Foreman is surfacing the option-(b)-vs-(a) trade-off to the King; this task captures option (a) so the fidelity gap is not lost.

FIX SHAPE: add a commit-SHA procurement path to install.sh (`--commit <sha>`: fetch + checkout the exact commit + procure/build its binary), then switch the harness recovery from `--channel edge` (or the SB_RECOVERY_REUSE_STAGED_BINARY gate) to `install.sh --commit <target-sha>`. Decide whether to keep the reuse-staged gate as a fast-path or remove it once the pin exists.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-12 02:42
---
RULED (architect, 2026-07-12). Verified first: install.sh's edge channel already contains the exact procurement --commit needs — checkout + procure sb from the commit-tagged image ghcr.io/statisticsnorway/statbus-sb:<short8> with in-container build fallback (install.sh:157-205); and the harness today runs `--channel edge` (vm-bootstrap.sh:562), which resolves MASTER AT RUN TIME — the exact unpinned drift the ticket names — while other bootstrap paths scp a locally-built binary, bypassing install.sh entirely.

(1) FLAG SHAPE: `--commit <full-40-hex-sha>` — mutually exclusive with --version and --channel (any combination refuses). FULL hex only: the commit-is-authoritative doctrine names artifacts by full SHA (CommitSHA vocab, doc/canonical-commit-naming.md), the harness has full SHAs in hand (B_FULL/C_FULL), and this flag's audience is the harness + developers — NSO operators stay on stable/prerelease. Anything not matching ^[a-f0-9]{40}$ refuses naming the rule. Semantics = edge-with-a-pin: clone or reuse ~/statbus, `git fetch origin <sha>` (an unpushed commit fails here naturally → the refusal says 'push it first'), `git checkout -B current <sha>`, VERSION = short8 of the sha (the rc.63 bare-short convention, same as edge), then the SAME downstream steps as edge — no second code path; factor the edge block's procurement into a shared function both channels call.

(2) IMAGE-VS-BUILD: --commit REFUSES when the image pull fails — no local-build fallback. Determinism is the flag's whole point: the harness must test the commit's PUBLISHED image (the artifact CI ships and the arc's upgrade legs will pull); a silent in-VM build would mask a CI-images gap and test a different artifact. The refusal is actionable: name the exact image ref, and the two remedies (wait for images.yaml to publish; use --channel edge if you genuinely want master HEAD with build fallback). Edge keeps its fallback unchanged — it serves the toolchain-free dev/rescue case.

(3) HARNESS SWITCH (the ticket's point): the per-commit bootstrap paths stop bypassing — vm-bootstrap's install invocation becomes `bash /tmp/statbus-install.sh --commit <sha-under-test>`; the scp-a-binary path remains ONLY for scenarios that deliberately construct non-install states, each with a one-line justification comment, so 'bypasses install.sh' is a named exception, never a default.

(4) ORACLE: (i) negative, cheap: --commit with a malformed sha refuses; --commit with a valid-but-unpublished sha refuses naming the image ref (both testable on any VM or even locally in seconds); (ii) positive, real: ONE existing arc run green end-to-end through the new bootstrap — the arc's install leg now IS install.sh --commit, so any green arc after the switch proves the flag on the operator's actual script. Engineer-scoped (install.sh + vm-bootstrap touch); queue behind the 160 build per the foreman's sequencing.
---

author: architect
created: 2026-07-12 02:42
---
ADDENDUM (architect, 2026-07-12) — the description's open question: the SB_RECOVERY_REUSE_STAGED_BINARY gate is REMOVED in the same package once --commit lands. It was the interim workaround for exactly the gap --commit closes; keeping it as a fast-path would be a standing bypass of the operator path with an env-var switch — the class the King's carve-out rules against. Internal clean-break: delete the gate and its env plumbing, convert its call sites to --commit, one commit.
---
<!-- COMMENTS:END -->
