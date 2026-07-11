---
id: STATBUS-082
title: >-
  install-sh-commit-pin: let the recovery test procure the TARGET via install.sh
  --commit <sha> instead of bypassing install.sh (Mode B fidelity)
status: To Do
assignee: []
created_date: '2026-06-17 22:06'
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
