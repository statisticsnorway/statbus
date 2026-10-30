---
id: STATBUS-208
title: >-
  vm-fleet-collision: same-name VMs across tag-fired workflows —
  refuse-then-delete kills the other run's live VM; project server limit
  breached
status: Done
assignee:
  - mechanic
created_date: '2026-08-16 20:54'
updated_date: '2026-08-27 13:50'
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
- [x] #1 Architect ruling on the structural remedy: run-scoped VM naming and/or scenario dedup across workflows, and the cross-workflow capacity design (concurrency budget vs limit raise vs retry-backoff)
- [x] #2 No VM is ever deleted by a run that did not create it — including the global orphan sweep's ownership discipline
- [ ] #3 A full tag-push fleet (test-install + install-recovery + arcs) completes with zero resource_limit_exceeded and zero cross-run interference — observed at an RC tag
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-16 20:56
---
STRUCTURAL RULING (architect, overnight — ruled NOW because rc.02 fires the same concurrent fleets at its tag: without these, the same collision and the same capacity breach recur by construction; the King's mandate is fixed-by-morning).

DEFECT A — RUN-SCOPED VM NAMES, ruled: every harness VM name gains a run-unique suffix (the GitHub run id's short tail) at the single name-derivation site in the harness lib — statbus-recovery-<slug>-<run-suffix>. Kills cross-workflow AND cross-run collisions permanently, composes with 207's ownership guard (defense in depth: names no longer collide, and even a collision could no longer delete a foreign VM). Length note for the builder: slugs are long — keep the suffix short (6-8 chars) and verify the longest slug stays within Hetzner's name limit; truncate the SLUG middle, never the suffix, if needed. The refuse-on-existing check stays byte-unchanged (with unique names it simply never trips cross-run; its orphan-catching duty passes to the prefix+age reaper, which is name-suffix-agnostic — verify the reaper matches on the statbus-recovery- prefix, not exact names). The 0-happy-install OVERLAP between the two workflows becomes harmless duplication (≈€0.01/tag) — KEEP both for now; de-duplication is a coverage-taste question for a later slimming pass, noted, not tonight's scope.

DEFECT B — CAPACITY BY CONSTRUCTION, ruled in two layers: (1) the VM-fleet workflows (install-recovery-harness, test-install, upgrade-arc-harness) SHARE one repo-scoped concurrency group (e.g. hetzner-vm-fleet) with cancel-in-progress: false — the fleets queue behind each other, so peak VM demand = one workflow's own max-parallel, which fits the account limit today without any account change. Cost: the tag's proof serializes (~sum of fleet durations overnight — acceptable; correctness beats wall-clock). (2) create-path retry-with-backoff on resource_limit_exceeded (bounded attempts, loud on exhaustion) as defense for residual contention (e.g. a straggler VM from the previous group still tearing down). MORNING OPTION for the King, account-level and his alone: raise the Hetzner project limit — after which the shared group can relax to parallel fleets; the ruling's parameters (group name, max-parallel) are tuned then, the mechanism stays.

LANE: all harness lib + workflow yaml — overnight-authorized, my review gates. ORACLES: name-derivation unit (suffix present, length bound, longest-slug case); the reaper prefix-match check; bash -n/shellcheck on touched regions; THE REAL ONE is rc.02's tag — both fleets green concurrently-queued, zero resource_limit_exceeded, zero foreign deletions.
---

author: foreman
created: 2026-08-16 20:57
---
Sequencing per architect: 207 (Stage-0 goal fix + ownership guard + verify-aggregation — aggregation ruled IN, extend-brief sent) lands FIRST; then this ticket builds — run-scoped VM names (run-id short suffix at the single name-derivation site, reaper matches prefix), ONE shared concurrency group across the three VM-fleet workflows (cancel-in-progress false — fleets queue; peak fits today's limit), bounded create-retry-with-backoff on resource_limit_exceeded, and the global orphan sweep's ownership discipline. Hetzner project limit RAISE stays on the King's morning list (account-level, his alone); the concurrency group relaxes after it. Assigned to mechanic as the follow-on unit — same files, warm context; he holds until his 207 freeze lands.
---

author: mechanic
created: 2026-08-16 21:25
---
BUILT, piece 1 (run-scoped VM names) and piece 3 (create-retry-with-backoff), both entirely inside test/install-recovery/lib/vm-bootstrap.sh's bootstrap_install_test_vm — confirmed this is the true single choke point: grep shows exactly ONE `hcloud server create` call site in the whole file, and ALL three workflows funnel through it (test-install.yaml's scenario + install-recovery-harness.yaml's scenarios both call bootstrap_install_test_vm directly; upgrade-arc-harness.yaml's arcs call it via arc-helpers.sh's arc_prepare_box). Zero changes needed to run.sh, scenario scripts, or arc scripts — they keep passing their existing 'logical' name (e.g. statbus-recovery-0-happy-install); the ACTUAL Hetzner-facing name is finalized inside bootstrap_install_test_vm, before the refuse-on-existing check and before VM_NAME is published to callers (matching the file's existing 'function sets a shared global its callers read afterward' convention, same one VM_IP/VM_EXEC already use).

New helpers (~line 110, right after _check_name_safety): `_run_suffix()` — last 8 chars of GITHUB_RUN_ID in CI, this process's $$ as the local fallback (no GITHUB_RUN_ID). `_suffixed_vm_name(base, suffix)` — appends -suffix, truncating base's MIDDLE (never the statbus-recovery-/statbus-arc- prefix, never the suffix) if the combined name would exceed Hetzner's 63-char limit.

Length-bound check, measured directly: longest current scenario slug is 33 chars (5-install-stage-d-advisory-zombie), longest arc slug is 34 (postswap-rollback-restore-watchdog). With an 8-char suffix: 17(prefix)+33+1+8=59 chars for scenarios, 12(prefix)+34+1+8=55 for arcs — NEITHER triggers truncation today. Built the truncation path anyway as a defensive guard per the ruling, and verified it with a synthetic over-length name: correctly produced a 63-char result with the prefix intact at the start and the full suffix intact at the end.

Retry-with-backoff wraps the create call: 5 attempts, 60s backoff, retries ONLY on a literal 'resource_limit_exceeded' match in hcloud's stderr; any other error fails on the first attempt; exhaustion fails loudly with the last attempt's hcloud stderr in the message.

All of the above verified with a stub harness (real vm-bootstrap.sh sourced, faked hcloud/ssh/scp/sleep — sleep stubbed to log instead of actually waiting) — not read-through:
- _run_suffix: CI path with a fake GITHUB_RUN_ID correctly extracts its last 8 chars; local-fallback path correctly returns $$.
- Retry: (a) resource_limit_exceeded twice then succeeds on attempt 3 — confirmed 2 stubbed 60s sleeps then success; (b) a DIFFERENT error text fails on attempt 1 with zero sleeps; (c) resource_limit_exceeded every time — confirmed exactly 5 create attempts, exactly 4 sleeps (none after the final failed attempt), loud exhaustion message with the hcloud stderr text included.

Oracles: bash -n clean. shellcheck identical to the git-show-HEAD baseline (current master, post-207) — 21→21, zero new findings.
---

author: mechanic
created: 2026-08-16 21:25
---
BUILT, piece 2 (shared concurrency group) and the ownership-discipline fold-in the ruling asked for.

PIECE 2: all three workflows now share `group: hetzner-vm-fleet`, `cancel-in-progress: false` — was install-recovery-harness/test-install/upgrade-arc-harness each on their OWN group before. Verified actionlint clean on all three after the change. Each workflow's concurrency-block comment updated to explain the shared-group rationale and cross-reference the other two.

OWNERSHIP DISCIPLINE — this went further than the two itemized pieces, and I want to flag exactly why rather than present it smooth. The run-suffix fix (piece 1) changes the ACTUAL VM name every workflow's reap/sweep steps target — three OTHER places in the owned YAMLs independently reconstruct that name (not by reading it back from vm-bootstrap.sh's state, which is gone by the time they run, but by re-deriving it from scratch), and all three needed updating or they'd silently reap nothing:

1. install-recovery-harness.yaml's 'Reap THIS scenario's VM' per-job step (~line 456) — was `vm="statbus-recovery-${SCENARIO}"`, now appends `-${run_suffix}` (GITHUB_RUN_ID's last 8 chars, computed identically to vm-bootstrap.sh's _run_suffix — the two formulas can only stay in sync by being textually identical, documented in-place on both sides).
2. upgrade-arc-harness.yaml's 'Reap THIS arc's VM' per-job step (~line 763) — same fix, `statbus-arc-${SCENARIO}-${run_suffix}`.
3. test-install.yaml's single reap step (~line 213) — redesigned entirely rather than patched: since this workflow provisions exactly ONE VM per run with a name now deterministically computable, I replaced its broad `grep '^statbus-recovery-'` prefix sweep with an EXACT-name reap (hcloud server describe/delete on the one specific name). A prefix sweep here had the SAME cross-run blast radius defect A itself exploited — it could delete install-recovery-harness's own live scenario VMs purely because they share the prefix, with no ownership signal at all. Since this workflow only ever needs to reap its own single VM, exact-name is strictly better than prefix+age here — no judgment call needed, no residual risk window.

SEPARATE FROM THE ABOVE — the two TRUE GLOBAL sweeps (install-recovery-harness.yaml's 'cleanup' job ~line 480, upgrade-arc-harness.yaml's equivalent ~line 818) can't target one exact name (they're deliberately catching orphans from ANY job in their own matrix that died before its per-job reap). Their existing comments claimed 'the ONLY place the cross-job sweep is safe — no sibling VM is live once all matrix jobs have finished' — TRUE only while each workflow was the sole user of its prefix. Post-208 that's no longer the full picture: hetzner-vm-fleet serializes the three WORKFLOWS but doesn't guarantee an instantaneous handoff — a straggler from the run just ahead in the queue could still be mid-teardown. Age-gated both sweeps instead of leaving them prefix-only: MIN_ORPHAN_AGE_MIN=150 (comfortably above both workflows' own 120-minute per-job timeout), using `hcloud server list -o json | jq` (not fragile column parsing) to get each candidate's `created` timestamp, `date -u -d ... +%s` for the age arithmetic. A VM that fails to parse is SKIPPED, never guessed-at. Updated both jobs' stale 'ONLY safe place' comments to explain why age-gating is now needed and what threshold protects against.

Verified the age-gating logic itself (not just read-through) against synthetic `hcloud server list -o json` output, using GNU date (gdate, matches the ubuntu-24.04 runner's coreutils — confirmed available locally, so I tested the EXACT bash+jq+date syntax, not an approximation): a 5-minute-old matching VM is correctly SKIPPED (below threshold), a 200-minute-old one is correctly REAPED, non-matching-prefix VMs (statbus-arc-*, a production VM) are correctly excluded by the jq filter entirely, and a malformed timestamp is correctly skipped with an explicit 'refuses to guess' message rather than silently mis-parsed.

Oracles: actionlint clean on all three workflows (re-verified after every edit, not just at the end). bash -n + shellcheck (21→21 vs git-show-HEAD baseline) unaffected by these YAML-only changes, re-confirmed anyway. Full diff stat: vm-bootstrap.sh +93/-8, install-recovery-harness.yaml +96/-16 (net, includes comment expansion), test-install.yaml +47/-16, upgrade-arc-harness.yaml +81/-9.

All four owned files, nothing else touched, no git commands run. This is the complete build for AC#1's ruled remedy (naming + capacity) and AC#2 (ownership discipline, including the global sweep). AC#3 (a real tag-push fleet, zero resource_limit_exceeded, zero foreign deletions) needs rc.02 — cannot be produced by me. Frozen; consolidated report going to the foreman via SendMessage.
---

author: foreman
created: 2026-08-16 21:28
---
LANDED as 4662b9147 on master, architect-approved with the scope expansion RATIFIED on all three pieces: (a) per-job reap suffix derived from the SAME env var as the lib's formula, must-match comment verified in the bytes (next-touch nicety recorded, not tonight: single-source the name via a job output so the reconstruction disappears); (b) exact-name reap strictly narrower, correct; (c) the age-gate ruled a SOUND cross-run-safe orphan definition — any VM older than every job timeout is an orphan by construction, so the sweep cannot touch a live run's VM; shipped sweeps use plain runner-native `date` (verified — gdate was local stubs only). AC#2 checked: ownership guard (207) + unique names + exact/suffix-matched reaps + age-gated sweeps together make foreign deletion impossible by construction at every deletion site. AC#3 (full tag-push fleet: zero resource_limit_exceeded, zero cross-run interference) is rc.02's observation. Tree is CLEAN — the overnight queue is complete.
---

author: foreman
created: 2026-08-16 22:30
---
ARC RUN COMPLETE (31970534502, overall failure): 21 arcs green, 10 red. SEVEN of the ten reds are THIS ticket's defect B verbatim — all died in ~60-70s at `hcloud: server limit reached (resource_limit_exceeded)` during the 20:29-20:34 stampede window (claim-without-notify, boot-migrate-churn-alive-idle, deploy-status-proof, failing, postswap-after-commit-kill, c-rollback-resurrection, cross-version-rename-handoff; two spot-verified in the logs, timing+duration signature identical across all seven). Everything started after ~20:44 — once install-recovery's fleet stopped competing — ran real scenarios. Superseded-by-construction claim: the landed fixes (shared fleet group + create retry) remove this class; rc.02 is the proof (AC#3). The remaining THREE reds ran post-stampede for 12-17 min and are genuine, now filed: STATBUS-209 (read-only completion INSERT after rollback restore — rollback-pair-terminal + restore-broke-reattempt, same invariant), STATBUS-210 (un-park destroyed by the flag-recovery classifier — un-park-to-completion), STATBUS-211 (crollback-fixed fixture seed image build failure — masked this run by capacity, deterministic at rc.02). Also noted: the three 197-observation preswap arcs (preswap-backup-kill, preswap-binary-swap-kill, preswap-checkout-kill) all GREEN at this tag, post-stampede.
---

author: foreman
created: 2026-08-17 07:16
---
rc.02 FLEET EVIDENCE, mixed verdict on this ticket's capacity design: v2026.08.0-rc.02 cut at 698228b09 (clean one-command run, no bless needed — the previous-RC comparison carries the blessed bytes). The shared hetzner-vm-fleet group WORKED for two workflows (test-install running, install-recovery correctly pending behind it) but FAILED at three: GitHub's group semantics hold one running + ONE pending — the third arrival CANCELLED the pending arc harness (run 32004847670, zero jobs). Defect B's zero-resource_limit_exceeded goal is so far holding; the serialization mechanism is superseded by STATBUS-214 (orchestrator workflow chaining the fleets explicitly — architect-ruled, dispatched to mechanic). INTERIM at rc.02: foreman's drain-then-dispatch monitor armed — hand-dispatches the arc harness at the tag once both fleet runs complete and the group is empty. AC#3's observation now spans the hand-dispatched arc run at rc.02 + the orchestrated fleet at the NEXT tag.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
VM fleet collision (landed 4662b9147, 2026-08-16): run-scoped VM names with suffix, shared concurrency group for serialization, create-retry-with-backoff on resource_limit_exceeded, ownership-guarded reap/sweep. AC#2 verified; AC#3: replaced by STATBUS-214 orchestrator for true cross-workflow coordination.
<!-- SECTION:FINAL_SUMMARY:END -->
