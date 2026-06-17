---
id: STATBUS-076
title: >-
  freshness-guard-fabricate: pre-staged HEAD sb trips git-diff bad-object on the
  VM's old-release clone (new dominant residual, rc.04 gate)
status: Done
assignee:
  - architect
created_date: '2026-06-17 11:26'
updated_date: '2026-06-17 12:25'
labels:
  - install-recovery
  - harness
  - rc.04
  - gate
  - freshness-guard
  - regression-triage
dependencies:
  - STATBUS-075
references:
  - cli/cmd/root.go
  - test/install-recovery/lib/wedge-helpers.sh
  - test/install-recovery/lib/data-helpers.sh
  - test/install-recovery/lib/vm-bootstrap.sh
  - cli/internal/upgrade/service.go
priority: high
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run 27683157288 (on 3a0d6e6dd). The SIGKILL-class quiesce (3a0d6e6dd) WORKED — log: "[quiesce] ✓ upgrade service SIGKILL-class quiesced (rollback handler NOT triggered; unit re-enableable)". So STATBUS-073's quiesce-rollback root cause is fixed. But a NEW deeper layer surfaced and is now the dominant residual.

SIGNATURE (2-preswap-binary-swap-kill:132 + 2-preswap-backup-kill:142 confirmed; expected on most fabricate+inject scenarios):
`fabricate_scheduled_upgrade_row psql failed (rc=2): freshness check failed: \`git diff\` exited 128.`
`stderr: fatal: bad object 3a0d6e6dd142490ac3b2a499888c68686ecd4963 — the build commit (3a0d6e6d) isn't in the local repo — rebuild from a tree that resolves it, or \`git fetch\`. After rebuild, re-run: ./sb config generate`

ROOT CAUSE: the harness pre-stages HEAD's sb binary (built at commit 3a0d6e6d) via scp (upload_sb_to_vm) onto a VM whose git repo is the OLD release (50fd4325f, shallow / single-branch clone at tag v2026.05.2). On `./sb psql`, the binary's freshness/staleness guard runs `git diff <build-commit=3a0d6e6d>` to verify the working tree matches the binary -> 3a0d6e6d is not an object in the VM's shallow old-release clone -> `fatal: bad object` -> git exits 128 -> freshness check fails -> `./sb psql` rc=2 -> fabricate fails BEFORE the real test.

EXPOSED BY the Category-C fix (9bdba03cc, `./sb config generate` before fabricate psql): config generate now SUCCEEDS (clears the prior REST_ADMIN_BIND_ADDRESS interpolation error), so `./sb psql` runs and hits the NEXT layer (the freshness guard). In RUN A the quiesce-rollback killed the scenario before fabricate's psql, masking this. Detected install state in both logs: "half-configured (current=2026.05.2, target=2026.05.2)".

CLASSIFICATION: HARNESS SCAFFOLDING, not a product upgrade bug. The infidelity = scp'ing a binary onto the VM without making its build commit resolvable in the VM's git repo. In production the binary's commit IS in the repo (the deploy branch moves + the box git-fetches). This is exactly the pre-staged-binary infidelity the branch-based real-upgrade-arc framework (STATBUS-071/034) eliminates.

FIX DIRECTION (harness-side, fix-forward, do NOT revert 9bdba03cc — that re-buries the Cat-C REST_ADMIN_BIND_ADDRESS error): make the build commit resolvable in the VM repo before fabricate runs `./sb psql` — `git fetch` the build commit (correct refspec for the shallow clone) or unshallow; OR extend the STATBUS_INJECT_AT staleness carve-out (cli/cmd/root.go) to cover the fabricate `./sb` calls. Product-graceful-on-absent-object (freshness guard treats a missing commit object as non-fatal) is a fallback the architect must weigh — it risks masking genuine staleness.

BLAST RADIUS: likely every fabricate+inject scenario that pre-stages HEAD + runs `./sb psql` (most of the suite). Operator to characterize as the run completes.

OWNER: architect (fix-shape decision: harness-fetch vs carve-out-extend vs guard-graceful) -> operator/engineer implement -> foreman review -> re-run. Blocks the rc.04 100%-green gate (STATBUS-075).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
OPERATOR DATA (2026-06-17): VM git setup = vm-bootstrap.sh. Release/tag install (line 549): `git clone --depth 1 --branch ${install_version}` (the 2-preswap scenarios = v2026.05.2). HEAD/edge install (line 520): `git clone --depth 50` + `git remote set-branches --add origin db-seed`. BOTH shallow -> the HEAD build commit 3a0d6e6d is not present (depth-1 single-branch old tag definitively excludes it). data-helpers.sh:331 ALREADY carries a comment flagging 'sb's freshness check on a depth-1 clone' as a known concern (never closed). Fabricate (data-helpers.sh:337-338): `./sb config generate && ./sb psql ...` runs with NO STATBUS_INJECT_AT and NO freshness bypass; the carve-out covers only the injected `./sb install`.

FOREMAN-FLAGGED TRAP for option (a): fetching the commit shifts the failure, doesn't fix it — fabricate runs the HEAD binary against a v2026.05.2 WORKING TREE, so `git diff 3a0d6e6d` becomes NON-EMPTY -> freshness guard sees STALE -> the original STATBUS-068 #2 self-heal `make` -> toolchain-free fail. Points toward option (b)/dedicated-bypass (the fabricate calls deliberately run new-binary-on-old-tree as setup, so they should skip the freshness check). Architect confirming from cli/cmd/root.go guard behavior whether (b) alone suffices.

DECISION (architect, foreman-verified 2026-06-17): FIX = option (d) REORDER-UPLOAD (harness-only, no product/bypass change). Move upload_sb_to_vm to AFTER fabricate_scheduled_upgrade_row in every fabricate+inject scenario. Rationale: fabricate only INSERTs a scheduled public.upgrade row (no HEAD schema/binary needed) so the tree-coherent OLD binary does it cleanly; the HEAD binary is only needed for the inject install, which ALREADY `git fetch --depth 1 origin HEAD && git checkout HEAD` itself (binary-swap-kill.sh:111-114) before `./sb install` — so the install is coherent and the ONLY binary<->tree mismatch is fabricate. Reorder removes the mismatch entirely → robust regardless of the warn-vs-fail anomaly (RUN A WARNed on the same 128, this run EXIT-2'd; data-helpers.sh:331 comment confirms the author expected a WARN — a deliberate product fail-fast hardening landed between). BONUS: with the old binary, fabricate's `./sb config generate` uses the old compose → the Cat-C REST_ADMIN_BIND_ADDRESS pressure also dissolves (9bdba03cc becomes belt). REJECTED: (b) carve-out-extend (broadens the gated STATBUS_INJECT_AT safety bypass to non-inject calls — semantically wrong); (c) guard-graceful (reverses a deliberate product fail-fast in check.go — masks a real binary-from-unknown-commit in prod). (a) harness-fetch = optional hygiene only (fetching makes the commit resolvable but leaves the stale tree → may still fail). IMPLEMENTATION: mechanic reorders across all fabricate+inject scenarios (preserve quiesce-before-fabricate + SB_VERSION_BEFORE capture after upload; flag any scenario whose fabricate needs HEAD for a raw-psql/old-binary fallback) -> architect reviews per-scenario -> foreman commits -> one re-run.

MECHANISM CORRECTION (architect, from cli/cmd/root.go + check.go, 2026-06-17): the earlier FOREMAN-FLAGGED TRAP note ('self-heal make -> toolchain-free fail') was WRONG on the mechanism (right on the conclusion). TRUTH: `./sb psql` is read-only (root.go:262) -> on stale it WARNs + proceeds, never exit-2. `./sb config generate` is MUTATING (not read-only; only `config show` is, :270) and NOT selfheal -> on stale it takes the non-selfheal mutating branch -> HARD-FAIL exit 2 (root.go ~159-162); NO `make` self-heal (that branch is selfheal-only). fabricate = `config generate && psql` -> config-generate exit-2s -> `&&` short-circuits -> psql never runs -> rc=2. So 'psql failed' is really CONFIG-GENERATE failing. CONSEQUENCE: (a) harness-fetch shifts 128->drift-exit-2 (config-generate still stale), does NOT fix. (b) is WORSE than first framed: it would bypass the freshness guard on a MUTATING (.env-writing) command = a real safety hole the King gates. (d) reorder is robust: old release binary on old release tree -> probeCommittedDrift same-commit SKIP (check.go:210) -> git diff never runs -> guard silent -> config-generate exit-0. No fetch, no bypass, no product change.

FOREMAN BYTE-LEVEL REVIEW of the mechanic's reorder diff (2026-06-17) — CAUGHT A DEFECT, commit HELD. The reorder was OVER-APPLIED. Verdict:
- CORRECT (7): 2-preswap-{backup,binary-swap,checkout}-kill, 3-postswap-{between-migrations,container-restart,mid-migration}-kill, 4-rollback-kill. Verified NO live pre-fabricate HEAD checkout → tree stays OLD at fabricate → old binary coherent.
- WRONG (2): 3-postswap-mid-tx-kill + 3-postswap-archivebackup-resume both do a LIVE HEAD checkout BEFORE fabricate (mid-tx-kill: VM_EXEC git checkout :154; resume: stage-head.sh :221). After the reorder, fabricate runs the OLD binary on a HEAD tree → IsStale=stale → `./sb config generate` (mutating, non-selfheal) HARD-FAILS. KEY FACT: v2026.05.2 HAS the staleness guard (git show v2026.05.2:cli/cmd/root.go → freshness import + stalenessGuard PersistentPreRun + IsStale), so the mechanic's 'predates the guard' rationale is FALSE.
CORRECTIONS: REVERT mid-tx-kill (its original checkout→upload-HEAD→fabricate was COHERENT, HEAD binary+HEAD tree; it wasn't even failing); archivebackup-resume = keep the early-upload removal but move upload to AFTER stage-head (:221) and BEFORE fabricate (:248) → HEAD binary+HEAD tree coherent. Routed to architect for confirm → mechanic corrects → architect re-reviews → foreman commits. The 5 'already correct' untouched scenarios are coherent fabricate-wise (early-upload HEAD binary + stage-head HEAD tree); watchdog + resume-died-rollback fail on the quiesce-mask (separate, STATBUS-073), not fabricate.

COMMITTED + PUSHED (foreman, 2026-06-17): reorder = 7f305f70d on master (e6c85c193 tip). 7 GO scenarios reordered (upload after fabricate) + archivebackup-resume corrected (upload after stage-head, before fabricate). mid-tx-kill VERBATIM REVERTED (git checkout --) — it never had the STATBUS-076 problem (HEAD-on-HEAD coherent), carries no diff. Architect design-confirmed + foreman byte-level reviewed + my 2 corrections applied/verified (bash -n + grep order). Status Done = the fix is landed; VALIDATION (green on the re-run) tracked by STATBUS-075. The current run 27683157288 is the freshness-residual evidence; the re-run on e6c85c193 confirms the fix.
<!-- SECTION:NOTES:END -->
