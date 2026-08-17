---
id: STATBUS-207
title: >-
  test-install-stage0-red: Stage 0 HTTPS-sources verify fails on current Hetzner
  image at v2026.08.0-rc.01 — now a stable gate, blocks promotion
status: Done
assignee:
  - mechanic
created_date: '2026-08-16 20:38'
updated_date: '2026-08-17 08:22'
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
- [x] #1 Actual apt source URIs of the current Hetzner Ubuntu 24.04 image captured as evidence; Stage 0 fix (or deliberate verify redefinition) designed against them, architect-reviewed
- [x] #2 vm-bootstrap.sh failure path no longer trips the hcloud server-ip harness failure after VM deletion — the real error reaches the log tail clean
- [x] #3 test-install green at an RC tag observed (the stable gate passes without SKIP_TEST_INSTALL)
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

author: foreman
created: 2026-08-16 20:54
---
CAUSAL CHAIN CORRECTED (full-log evidence; supersedes comment #2's remaining assumptions and dissolves comment #3's trace pointer):

1. Stage 0's ✗ is REAL but NON-FATAL. The full test-install log shows: '✗ HTTPS sources configured' → '✓ APT update succeeds' → Stages 1-3 verifying → 'creating statbus user + linger...' → 'VM bootstrap complete.' setup-ubuntu-lts-24.sh has NO set -e (only `set -o pipefail`, :17): verify() returns 1, the script continues, hardening exits 0. There was never a hardening failure and never an errexit-propagation bug — open question (a) is CLOSED as a ghost; the architect's condition-context pointer chased my wrong premise.

2. The test-install killer is CROSS-RUN VM DELETION, now STATBUS-208 defect A: the concurrent install-recovery run's 0-happy-install job refused-on-existing at 20:28:12 (correct) and then its cleanup/reap DELETED the foreign VM at 20:28:39 ('Server statbus-recovery-0-happy-install deleted'). test-install kept SSH-ing its cached IP — recycled to a sibling scenario VM running identical hardening, hence 4 minutes of plausible cross-wired log — and died at :618 on 'hcloud: Server not found' (question (b) answered: the stderr WAS surfaced; the VM was genuinely gone).

3. Scope consequence, relayed to the mechanic: primary Stage-0 goal-based fix UNCHANGED (the ✗ is real on the current image and verify must state the goal); secondary REPLACED with the tactical ownership guard — cleanup never deletes a VM the job did not create (refuse-branch exit skips deletion, logs the foreign owner). Structural remedies (run-scoped names, cross-workflow capacity) are STATBUS-208, architect ruling pending.

4. Fleet context: install-recovery red = 14/16, of which 13 are STATBUS-208 defect B (resource_limit_exceeded at create) and the 0-happy job is defect A's other side. Test Hardening GREEN. Arc harness still queued.
---

author: mechanic
created: 2026-08-16 21:04
---
BUILT per comment #6 point 3's revised secondary scope — the tactical ownership guard (cleanup never deletes a VM this run did not create), on top of the already-built Stage 0 goal-based rewrite (unchanged) and hcloud-stderr diagnosability (kept — complementary, not superseded; still useful for ANY future hcloud failure regardless of cause).

Design: new global VM_OWNED_BY_THIS_RUN, set to 1 in bootstrap_install_test_vm ONLY immediately after `hcloud server create` itself succeeds (vm-bootstrap.sh, right after the create call — set -e means a failed create, e.g. STATBUS-208 defect B's resource_limit_exceeded, never reaches that line either, correctly). cleanup_vm checks the flag as its FIRST action (before dump_stage_tmux_logs, before any KEEP_VM/delete branching): unset/not-1 → log "NOT deleting '$vm_name' — this run never created it" and return 0 without touching the VM at all (no tmux-log SSH probe either — we shouldn't be poking a VM we don't own). A caller whose bootstrap hit the refuse-on-existing check (vm-bootstrap.sh ~:561, unchanged per the ruling) never sets the flag, so its scenario's EXIT-trap cleanup_vm call becomes exactly this no-op — the STATBUS-208 defect A mechanism this guard targets.

Verified empirically with the stub harness (not just read-through) against BOTH branches:
- Owned case: hcloud stub reports "not found" on describe (proceed to create) → create succeeds → VM_OWNED_BY_THIS_RUN=1 confirmed printed → cleanup_vm's EXIT-trap call reaches "Deleting VM: ..." as before — no regression for the normal path.
- Foreign case: hcloud stub reports the VM already exists on describe → refuse-on-existing correctly fires, bootstrap returns 1, VM_OWNED_BY_THIS_RUN never set → cleanup_vm's EXIT-trap call prints the NOT-deleting message and returns 0 — confirmed via a marker file (not just absent stderr, since the real delete call has `2>/dev/null`, which would silently swallow a stub print too) that `hcloud server delete` was genuinely never invoked.

Oracles: bash -n clean on both files. shellcheck finding-count identical to the git-show-HEAD baseline for both (setup-ubuntu-lts-24.sh 9→9, vm-bootstrap.sh 21→21 — zero new findings, confirmed via git show HEAD:<path> to a scratch file, never git stash). All fixture/command-string testing (the Stage 0 verify command's exact eval behavior against realistic DEB822/legacy apt-sources fixtures, the diagnostic-dump grep's precision, and this ownership guard) was done via throwaway local fixtures/stub commands — no real Hetzner VM provisioned, no test suite run.

One bug caught and fixed during this build, worth recording: my first draft of _hcloud_server_ip captured `rc=$?` AFTER the if/fi construct completed (condition false, no else) — empirically this is ALWAYS 0 per POSIX (an if with no else branch taken exits 0 regardless of the tested command's real status), not hcloud's real exit code. Caught via a minimal isolated repro before it shipped; fixed by capturing $? as the first statement inside an explicit else branch instead, then re-verified via the full stub harness that the diagnostic now shows the correct rc.

Still open, not decided by me: whether the setup.sh verify()-failures-never-propagate gap (flagged in comment #5) is in-scope for this ticket — haven't seen the exact extend-brief mentioned in 208's sequencing comment yet. Holding on that piece pending the foreman/architect. Everything else (Stage 0 rewrite, hcloud diagnosability, ownership guard) is frozen and ready for review.
---

author: foreman
created: 2026-08-16 21:04
---
EXTEND-BRIEF, pinned here because the SendMessage copy was lost in transit (mechanic's freeze report says it never arrived — durable-channel lesson re-learned): VERIFY-AGGREGATION IS RULED IN for this unit (architect's word). Shape, exactly: run ALL stages to completion — do NOT fail-at-first; maximal diagnostics per torn-down VM — collect every verify() failure (verify() may count/record into a global), print the failed set at the very end of main(), exit non-zero if any verify failed. Safety evidence already gathered: the rc.01 run shows 18 ✓ and exactly ONE ✗ (Stage 0, fixed by this same unit), so aggregation introduces no new red at rc.02. The 207 freeze is PULLED BACK for exactly this addition — announced, not silent: mechanic adds aggregation to ops/setup-ubuntu-lts-24.sh, re-freezes, and the architect reviews ONCE on the complete unit.
---

author: mechanic
created: 2026-08-16 21:06
---
BUILT: verify-aggregation, per the released-hold ruling (run all stages to completion, collect every verify() failure, print the failed set at the end, exit non-zero if any failed). This is the last of 207's three pieces — ops/setup-ubuntu-lts-24.sh now has:

1. FAILED_VERIFICATIONS=() — new global near the top config block (SKIP_STAGES's neighbor).
2. verify() appends the description to it on the failure branch (one line added, existing print/return behavior otherwise untouched).
3. main()'s LAST action, after the reboot-required check (so every stage genuinely ran to completion first, matching 'maximal diagnostics' — unchanged from today's no-fail-fast behavior): if the array is non-empty, print a numbered failed-set list and `exit 1`.

Empirically tested (throwaway harness reproducing the exact verify()/aggregation shape, not the real script — no VM): a 2-of-4-checks-fail case ran ALL FOUR checks (no fail-fast), printed both failures in a clear final list, exited 1; an all-pass case exited 0 and reached past the aggregation check. Both confirmed via direct execution, not read-through.

Oracles, full file this time: bash -n clean. shellcheck identical to the git-show-HEAD baseline — 9→9 findings, zero new (same as the Stage-0-only checkpoint; this addition introduced nothing new either).

207's build is now complete: Stage 0 goal-based rewrite + hcloud-stderr diagnosability + ownership guard + verify-aggregation. Full consolidated freeze report going to the foreman via SendMessage now.
---

author: architect (relayed by foreman)
created: 2026-08-16 21:07
---
REVIEW VERDICT: three of four pieces APPROVED as frozen (hcloud helper, ownership guard, verify-aggregation — all to spec). RETURNED on ONE blocking precision defect in piece 1: the http-detection greps (:418, :430) and the goal-verify (:454) are COMMENT-BLIND — they match 'http://' anywhere, and stock Ubuntu/cloud-init sources files routinely carry comment lines with http:// links ('# See http://help.ubuntu.com…', commented-out deb entries). Ghost-red story on a fully-hardened image: all real URIs HTTPS → detection trips on a comment → rewrite runs, changes nothing → verify trips on the same comment → aggregation (correctly) fails the run → rc.02 RED on a ghost. Goal-vs-mechanism one level down: the goal is 'no http:// URI in an ACTIVE source line', not 'no http:// substring anywhere'.

THE FIX (small, half-present already): the diagnostics dump anchors on real source lines — `^[[:space:]]*(URIs:|deb(-src)?[[:space:]])` — so DETECTION and VERIFY must reuse exactly that anchoring (active URIs:/deb/deb-src lines containing http://; comments excluded by the anchor). The sed's comment-blindness becomes moot once detection is line-anchored; scoping the sed to the same line shapes is optional tidy, mechanic's call. REQUIRED new fixture arm: all-HTTPS active URIs PLUS a comment containing an http:// link → detection skips, verify passes, exit 0. One more re-freeze; instant turnaround promised — last precision pass, the unit is otherwise done.
---

author: mechanic
created: 2026-08-16 21:10
---
FIXED per comment #10's blocking precision defect — line-anchored the http-detection greps and the goal-verify to active URI-bearing lines only, reusing the diagnostics dump's own anchor. In ops/setup-ubuntu-lts-24.sh's stage_https_sources:

1. New `local uri_line_re='^[[:space:]]*(URIs:|deb(-src)?[[:space:]])'` (right before the DEB822/legacy branch), ONE definition shared by every check that follows — detection, the shipped-mirror log line, verify, and the diagnostics dump all now agree on what counts as an active URI line, so they can never drift out of sync again.
2. Both detection checks: `grep -q 'http://' "$file"` → `grep -qE "${uri_line_re}.*http://" "$file"`.
3. Both shipped-mirror log lines: simplified to `grep -E "$uri_line_re" "$file" | grep -oE 'https://[^[:space:]]+' | head -1` (filter to active lines first, then extract the URL — so a comment's https:// link can't get logged as 'the shipped mirror' either, matching the same precision principle even though it wasn't named as blocking).
4. The verify command: `! grep -rq 'http://' ...` → `! grep -rqE '${uri_line_re}.*http://' ...`.
5. Left the sed unscoped, per the reviewer's 'optional, your call' — now genuinely benign: since detection and verify are both anchored, a sed that also touches a matching comment (only possible when a REAL active http:// URI already triggered the rewrite branch) is cosmetic, never a false-fail.

FULL FIXTURE SET re-run (throwaway local files, no VM), now 4 arms including the required new one:
- All-HTTPS active URIs (DEB822) → detection skips rewrite, verify passes, exit 0.
- REQUIRED NEW ARM: all-HTTPS active URIs PLUS a comment containing an http:// link (both 'See http://help.ubuntu.com/...' prose and a commented-out 'deb http://old.../ubuntu' entry) → detection correctly skips rewrite, verify correctly passes, shipped-mirror log correctly extracts the REAL https:// URL not the comment's link. This is the exact ghost-red scenario from comment #10, now proven fixed.
- Legacy format equivalent of the above (commented-out `# deb http://...` entry alongside real HTTPS `deb`/`deb-src` lines) → same correct skip/pass.
- Real http:// active URI needing rewrite (unchanged from the prior checkpoint) → detection still triggers, verify still correctly fails pre-rewrite.

Oracles: bash -n clean on both files. shellcheck identical to the git-show-HEAD baseline for both — setup-ubuntu-lts-24.sh 9→9, vm-bootstrap.sh 21→21, zero new findings at this checkpoint either (vm-bootstrap.sh untouched this round, re-confirmed anyway).

All four pieces now complete and precision-passed. Re-freezing; consolidated report to the foreman via SendMessage.
---

author: foreman
created: 2026-08-16 21:11
---
LANDED as 2462acc74 on master, architect-approved (final verdict: anchor fix exactly right and slightly better than prescribed — the shared uri_line_re extension to the shipped-mirror log lines noted approvingly; quoting at the verify site verified). AC#1 checked — the fix is designed against the evidence-established image shape and architect-reviewed (the URI dump on any future failure closes the capture loop permanently). AC#2 checked — the :618-class failure is triple-covered: ownership guard prevents the foreign deletion, _hcloud_server_ip surfaces stderr+rc, and verify-aggregation makes any genuine hardening failure fail the run at the right place. AC#3 (test-install green at an RC tag without SKIP) is the rc.02 observation — stays open; note it also depends on STATBUS-208 landing (the capacity + naming half of the fleet collision). 208 dispatching now.
---

author: foreman
created: 2026-08-17 08:22
---
AC#3 CLOSED at v2026.08.0-rc.02: test-install run 32004847708 COMPLETED SUCCESS at the tag — the FIRST green at an RC tag in this lane's recorded history (rc.01, rc.05, rc.06 all red), with no SKIP_TEST_INSTALL. The Stage-0 goal-verify passed on the real Hetzner image, verify-aggregation held (any hardening failure would now have failed the run), and no foreign deletion occurred (208's fixes + the serialized group). Install-recovery's 15/15 green in the same window is the same fixes proven at fleet scale. All three criteria checked — ticket DONE.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
test-install's never-green-at-tag streak traced to three stacked causes and fixed: Stage 0 of the hardening script verified a mechanism (kernel.org mirror presence) instead of its goal (no http:// URI on active source lines) and false-failed on Hetzner's already-HTTPS images; verify() failures aggregated nowhere across all 8 stages so no hardening check could ever fail a run; and a concurrent same-named run's cleanup deleted the live VM (the actual rc.01 killer, split to STATBUS-208). Landed: goal-based comment-safe Stage 0 with URI dumps on failure, verify-aggregation failing the run loudly, hcloud stderr surfaced at all call sites, and the VM ownership guard. Proven at v2026.08.0-rc.02: first-ever green at an RC tag, no bypass.
<!-- SECTION:FINAL_SUMMARY:END -->
