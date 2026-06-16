---
id: STATBUS-065
title: >-
  selfheal-toolchain-free: ./sb install staleness self-heal shells `make` →
  fails (127) on toolchain-less hosts → operator can't recover a post-swap crash
status: In Progress
assignee: []
created_date: '2026-06-16 12:02'
updated_date: '2026-06-16 13:12'
labels:
  - upgrade
  - recovery
  - install
  - robustness
  - north-star
  - architect-plan
dependencies: []
priority: high
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PRODUCTION-RELIABILITY GAP surfaced by the install-recovery harness (2-preswap-checkout-kill (a), CI run 27614658333). North-Star-critical (STATBUS-039: the operator's one recovery action must work on the actual deployment hosts, which have NO Go toolchain).

## Mechanism (foreman-verified, file:line)
- cli/cmd/root.go:62 `PersistentPreRun: stalenessGuard`. root.go:112 `freshness.IsStale(ProjectDir, commitSHA)`; root.go:124 if the command is annotated `selfheal=true` (e.g. `./sb install`) and stale → `freshness.RebuildAndReexec(ProjectDir)`.
- cli/internal/freshness/rebuild.go:19/37 — RebuildAndReexec runs `exec.Command("make", "-C", "cli", "build")`.
- On a host with NO Go/make toolchain (production deployments) → `make build` exits 127 → "Self-heal rebuild/exec failed: rebuild failed: exit status 2" → the command ABORTS. The staleness model assumes a DEV host (check.go:195 suggests `./dev.sh build-sb`).

## Reachability (architect to map fully)
A post-swap-crash recovery has binary=NEW (image-extracted + swapped) while tree=OLD (checkout deferred, STATBUS-060). The operator's canonical recovery `./sb install` (selfheal=true) → stalenessGuard → STALE → `make` → 127 → CANNOT RECOVER on a toolchain-less host.
- BOUNDED: 0-happy-upgrade is GREEN on the toolchain-less VM, and it recovers via the systemd `./sb upgrade service` daemon — so the DAEMON path does NOT trip this. The gap is specifically the operator `./sb install` path (confirm).

## Fix direction (architect design; run by King before code)
Make the self-heal TOOLCHAIN-FREE: re-procure the binary via image-extract (mirror 09ac1f7e4 procureSbFromImage: `docker create statbus-sb:<short>` + `docker cp`), NOT `make`. OR: do not treat the legitimate binary-ahead-of-tree recovery state as "stale-needs-rebuild" (checkout the tree to match the binary first, then proceed). Keep the dev-host `make`/`./dev.sh build-sb` path for dev iteration.

## Why it gates rc.04
- It's why (a) 2-preswap-checkout-kill dies (before recovery) → rc.04's from_commit_sha PRIMARY path is unvalidated.
- It will also break STATBUS-060's real-install.sh recovery (install.sh runs `./sb install` → trips this on a toolchain-less VM).
OWNER: architect. Aligns with STATBUS-039 + the toolchain-free design (09ac1f7e4).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
VERDICT: REAL gap (architect map + foreman-verified firsthand 2026-06-16). selfheal=true on install.go:102 (operator install) + upgrade.go:262 (upgrade service / DAEMON) + :489 (apply-latest) — so operator AND daemon are exposed (0-happy was a vacuous-cli-diff pass, not daemon-exempt). Swap timing: replaceBinaryOnDisk service.go:4007 → updateFlagPostSwap:4033 → handoff (os.Exit(42):4045 / syscall.Exec:4051) → binary=NEW/tree=OLD arises POSTSWAP. stalenessGuard (root.go:62 PersistentPreRun) runs BEFORE the recovery-boot checkout → IsStale → make (rebuild.go:37) → 127 on toolchain-less hosts. Latent today only because cloud (niue) has Go; bites the toolchain-less EXTERNAL-STANDALONE target hosts + the install-recovery VMs.

FIX B (architect, recommended; presented to King for approval): make stalenessGuard recovery-aware — before self-heal/hard-fail, upgrade.ReadFlagFile (service.go:621, exported, callable from root.go); if a service-held flag is present, the binary-ahead-of-tree state is the EXPECTED in-flight recovery state → WARN + PROCEED (skip rebuild), the recovery-boot checkout reconciles tree→binary. Keep self-heal/hard-fail for the no-flag dev-stale case. ~10 lines, toolchain-independent, covers operator + daemon.
FIX A (image-extract self-heal instead of make): REJECTED — rebuild-to-match-tree would discard the NEW binary; addresses the toolchain symptom not the wrong-to-rebuild-during-recovery cause.

LINCHPIN: unblocks the (a) 2-preswap-checkout-kill scenario (trips the same guard) + STATBUS-060's real-install.sh recovery on toolchain-less hosts. (a) REVISED: keep it (065 unblocks it → validates the from_commit_sha PRIMARY path e2e) + add a structural guard; no retire. OWNER: architect (root.go + freshness helper). Aligns with the external-standalone arc + STATBUS-039.

REACHABILITY VERIFIED (foreman firsthand, 2026-06-16, all 4 facts file:line-checked): (1) stalenessGuard=PersistentPreRun root.go:62 → precedes RunE; (2) IsStale drift probe check.go:213 `git diff --quiet <binary> <HEAD> -- cli/` is DIRECTION-AGNOSTIC → binary-NEW/tree-OLD trips for any cli/-touching upgrade; (3) post-swap shape: service.go:4007 swap → 4033 post_swap stamp → 4045 exit-42, NO checkout between (STATBUS-060 deferred to recovery boot service.go:1518); (4) tagged-release procures PREBUILT (replaceBinaryOnDisk 4007, no toolchain) vs edge=make 4010 → guard's make root.go:127 is the SOLE spurious toolchain demand. VERDICT: REACHABLE on daemon `./sb upgrade service` post-swap, tagged-release channel, toolchain-less host (the external-standalone target). Bare `./sb install` NOT production-reachable (operators go via install.sh which pre-aligns tree+binary, install.sh:170,186). 0-happy's green is a VACUOUS-cli-diff pass, not daemon-exemption. GREENLIT Fix B (scoped). Clean-break impl: extract predicate (already dup'd at service.go:1495-1497 + install_upgrade.go:178-180) into one `(*FlagFile).IsServiceForwardRecovery()` method, 3 callers; guard defers inside the selfheal branch before RebuildAndReexec; unit-test the predicate. Architect implementing; foreman reviews diff before commit.

IMPLEMENTED + COMMITTED 768a95d85 (foreman byte-level reviewed firsthand, build/vet/test green). Clean-break: UpgradeFlag.IsServiceForwardRecovery() is the single predicate (def at service.go:296), 3 live callers (root.go:136 stalenessGuard selfheal-branch defer; service.go:1518 Run recovery-boot gate; install_upgrade.go:178 runCrashRecovery gate). Guard now defers to the recovery boot on a service-held FORWARD-phase flag instead of shelling make; genuine stale-dev (no flag / install-held / pre_swap) still self-heals; PreSwap gated out. 7-case predicate unit test (flag_recovery_test.go) passes. NOTE: the method def first landed in the preceding rename commit 6f1b3a02f via a concurrent shared-tree edit (amended that commit's message to state it; nothing was pushed). E2E validation (daemon post-swap recovery on a toolchain-less VM with a cli/-touching upgrade) rides the comprehensive install-recovery run — keep In Progress until that is green.
<!-- SECTION:NOTES:END -->
