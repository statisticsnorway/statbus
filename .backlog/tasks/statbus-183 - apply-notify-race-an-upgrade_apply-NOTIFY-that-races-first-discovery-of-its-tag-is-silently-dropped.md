---
id: STATBUS-183
title: >-
  apply-notify-race: an upgrade_apply NOTIFY that races first discovery of its
  tag is silently dropped
status: To Do
assignee: []
created_date: '2026-07-14 16:12'
updated_date: '2026-07-14 17:06'
labels:
  - upgrade
  - deploy
  - fail-fast
  - defect
dependencies: []
priority: medium
ordinal: 184000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a delivered apply poke either schedules the named version or fails LOUDLY — never a silent no-op that leaves the row available and the operator believing the deploy is in flight.
> FOUND: 2026-07-14 ~18:00, rc.06 canary on rune (live box, read-only diagnosis). deploy-via-upgrade run 29347796677 delivered `NOTIFY upgrade_apply, 'v2026.07.0-rc.06'` and exited green. Journal: the daemon DISCOVERED the tag at 18:00:31 (signature verified, "Discovered: v2026.07.0-rc.06"), verified + pre-downloaded all images by 18:02:07 — and then nothing. 25+ minutes later the row (id 42843) sat state='available', scheduled_at NULL, docker_images_status=ready, release_builds_status=ready, not parked, daemon unit active. The apply was dropped: the NOTIFY arrived while the tag was not yet a registered candidate (the release was ~4 minutes old; the poke raced the box's own first discovery of it), and whatever the handler did between "trigger discovery" and "schedule the named version," the scheduling half never happened — with zero error surfaced anywhere.
> CONTRAST: the rc.05 poke on the same box (same workflow, same shape) went row-completed in 78 seconds — the tag had been discoverable longer. Timing is the only visible difference.
> REMEDY USED: a second identical poke (run 29348619144) — the row then existed registered with images ready. The canonical operator retry works; the silence is the defect.
> RELATION: the STATBUS-170 arc one level deeper — 169 fixed green-means-scheduled lies, 170 makes green mean converged; this is "even the poke can be lost silently." 170's phase-2 polling would have caught this in CI (timeout → red naming 'available'), which is evidence for its priority, but the product should not drop a delivered apply either way.
> COMPLEXITY: engineer trace first (find the exact drop site in the apply handler: does it resolve the tag BEFORE its own check completes? does an error get swallowed?), then architect rules the fix (make apply wait-for/trigger registration then schedule, or fail loudly to the poke's output).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Engineer traces the exact drop site in the upgrade_apply NOTIFY handler with file:line (why discovery ran but scheduling didn't, and where the error went)
- [ ] #2 Architect rules the fix shape: apply always either schedules the named version (registering it first if needed) or fails loudly
- [ ] #3 Fix proven by a run: a poke sent within seconds of a fresh release schedules correctly (or fails loudly) — no silent available-forever row
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer (relayed by foreman)
created: 2026-07-14 16:28
---
DROP-SITE TRACE (engineer, 2026-07-14, read-only) — AC#1 checked; the ticket's 'between discovery and schedule' framing CORRECTED: the apply handler never triggers discovery at all. Chain: service.go:2394 `case "upgrade_apply"` does NOT call d.discover() (contrast :2393 upgrade_check, which does) → :2406-2413 onScheduledNotify → :4112 resolveUpgradeTarget → commit.go:279 git-first RevParse resolves the tag WITHOUT any DB row → service.go:4152-4167 the promote UPDATE touches only an existing row (STATBUS-086 deliberately removed insert-if-missing) → 0 rows → :4176-4183 EXISTS probe false → :4184+:4195-4199 classifyScheduleResult=unregistered → fmt.Printf 'NOTIFY upgrade_apply for UNREGISTERED commit … — ignored. Register it first' → return. THE DROP: a plain stdout line, void return, no DB write, nothing the poke (already exited, :4099) or any later reader can see — and the independent discovery registers the row moments later as plain 'available', never re-firing the apply. FIX-SHAPE READ (architect to rule): code structure favors (A) inline register-then-schedule in the unregistered branch — resolveUpgradeTarget already returns a git-resolved SHA+Tag and upsertCandidate exists at :3497; re-run the promote after upsert. CAVEAT for the ruling: (A) narrows STATBUS-086's require-register doctrine — but the principled line is visible: 086 forbade inserting UNKNOWN commits; a GIT-RESOLVABLE, signed, image-ready release tag racing its own discovery is a different class. (B) fail-loudly-to-the-poke is structurally unreachable from the async NOTIFY handler (no channel back); its honest realization would be moving the deploy poke to synchronous `./sb upgrade schedule`, which still needs register-first on the race.
---

author: architect
created: 2026-07-14 16:41
---
FIX SHAPE RULED (architect, 2026-07-14) — AC#2. Verdict: (A) inline register-then-promote in the unregistered branch, PLUS a fetch leg at the :4115 sibling, PLUS a durable refusal signal on every refuse path. The 086 question adjudicated below does NOT rise to King-bless in my judgment (rationale at the end); foreman may FYI him this evening.

1. THE 086 ADJUDICATION — properly stated, this is a RELOCATION, not a narrowing. What 086 actually forbade (its own text, service.go:4192-4199 + errNotRegistered) is the old scheduleImmediate's BLIND schedule-side insert — a row created with no verification. The ruled fix creates rows ONLY through the guarded register machinery itself: the unregistered branch calls upsertCandidate (:3497), which carries the STATBUS-169 write-guard INTERNALLY (:3507-3509, tag↔commit pointing verification with the annotated-tag peel) — so the foreman's carry-over question answers itself structurally: the guard cannot be bypassed because it lives inside the only function that may insert. The surviving invariant, stronger than the old phrasing: NO CANDIDATE ROW IS EVER CREATED EXCEPT BY THE GUARDED REGISTER PATH. Scope: any target class the CLI register verb itself accepts, with that class's guards — TaggedTarget via the 169 guard; UntaggedTarget via the rc.04-night fetch+object verification — because the fix then automates EXACTLY the remedy the drop message already prescribes ('Register it first: ./sb upgrade register …'), with identical guards and identical refusals. Risk bound that makes this safe: scheduling is not the execution boundary — a scheduled row still passes verifyArtifacts/images gating before executeUpgrade runs anything, so a garbage-but-resolvable input dies loudly at artifact verification, never executes.
2. THE :4115 SIBLING — YES, add the fetch leg. A NOTIFY that beats the box's own fetch of a genuinely-cut release must converge, not loud-ignore: ONE targeted fetch attempt (reuse the register-by-commit fetch mechanism from the rc.04 fix; tags fetch their ref the same way) before resolveUpgradeTarget, inside the handler — a single attempt, never a backoff loop in a NOTIFY handler. Resolve still failing after the fetch = the input names nothing that exists → refuse, now durably (point 3).
3. DURABLE REFUSAL SIGNAL — owed regardless, on EVERY refuse path of the apply handler (unresolvable-after-fetch; upsert refusal from the 169 guard; any future refuse). Write system_info key `upgrade_apply_refused` = JSON {input, reason, occurred_at} (the daemon already owns system_info writes, :2987 genre); CLEARED on the next scheduleResultPromoted. stdout stays for the journal; the key is what STATBUS-170 phase-2 and the admin UI can read — the poll then distinguishes 'no row + named refusal' (red, actionable) from 'no row + nothing' (in flight). This directly kills the incident's silence class even for refuse paths we have not imagined yet.
4. RACE HYGIENE (engineer verifies at build): the incident's actual race — inline register vs the independent discovery registering the same tag moments later — must be benign via upsertCandidate's conflict handling (idempotent upsert on commit_sha); confirm and unit-test both orders. After a successful inline register, re-run the SAME promote UPDATE (the code is already shaped for it) so supersedeOlderReleases fires on the promoted path exactly as today.
5. ORACLE (AC#3): unit tests on the unregistered branch (resolvable tag → registered+promoted with the 169 guard exercised; unresolvable-after-fetch → durable refusal written; refusal cleared on next promote) + the run: the next RC's deploy poke sent within seconds of the cut — the natural repeat of this incident — must converge row-completed. 170 phase-2 stays the independent net.

WHY NO KING BLESS: his 086 intent (no blind inserts; loud actionable refusals) and his 169 guard both run UNCHANGED — only the invoker of the already-sanctioned register machinery moves from the operator's hands into the handler, for inputs the operator's own remedy command would have accepted identically. Nothing in the permission/verification surface weakens; one silent path becomes convergent and every refusal becomes durable. If the King reads it differently this evening, the build waits on his word — the engineer can start on points 2-4, which stand regardless.
---

author: architect
created: 2026-07-14 17:06
---
SAFETY-CORE PASS on the frozen build (architect, 2026-07-14): AMEND before commit — one real defect found and EMPIRICALLY confirmed; everything else ships as built.

THE DEFECT (A1, mandatory): the fetch leg is VACUOUS for the exact rc.06 incident case. ensureCommitLocal's fetch is `git fetch origin <input>` — correct for a full SHA (the rc.04 deploy-by-commit case it was built for), but for a TAG NAME git fetches into FETCH_HEAD ONLY and does NOT create refs/tags/<tag>; the subsequent resolveUpgradeTarget RevParse still fails. Reproduced in a scratch repo just now, clean clone, tag created on the remote after: plain `git fetch origin vtest-2` → `* tag vtest-2 -> FETCH_HEAD`, rev-parse still fatal; the refspec form `git fetch origin refs/tags/vtest-2:refs/tags/vtest-2` → `[new tag]`, rev-parse succeeds. As frozen, the rc.06 race would now end in a DURABLE REFUSAL instead of silence — an improvement — but not the ruled CONVERGENCE. Fix: class-branch the fetch inside ensureCommitLocal (one chokepoint, mirrors registerTarget's design): cat-file short-circuit unchanged; on miss, isCommitSHAShape → the current SHA fetch; else → `git fetch origin refs/tags/<input>:refs/tags/<input>`. Also generalize its error text — it currently says "register could not fetch commit … deploy-by-commit", the wrong voice for the apply/tag path. RunRegister's SHA-gated call keeps identical behavior.

A2 (mandatory, cheap): the 7 tests did not catch A1 — TestApplyRace_FetchLegBeforeResolve asserts call ORDER only. Add a structural assert that the tag-class fetch uses the refs/tags refspec form (funcBody contains `refs/tags/`), with a comment citing the FETCH_HEAD-only behavior so nobody simplifies it back.

A3 (verify-or-tighten): the foreman's blocking-hazard question — runCommandOutput bounds every command at 2 MINUTES (exec.go:226-232, context timeout; verified), so no unbounded hang. But 2m sits at the unit watchdog window's scale: builder either confirms the notify-dispatch path stays heartbeat-covered through a 2m block, or passes a shorter bound (~30s — ample for a single ref fetch) for the handler call.

ADJUDICATIONS — the rest ships as built:
- THE DEVIATION (clear refusal on scheduleResultAlreadyScheduled): ACCEPTED. The key's semantics are single-latest-outcome; an already-scheduled/running named version means the poke's intent IS actioned, and a stale refusal beside it would be a false red for 170 phase-2. The engineer's rationale is correct and consistently applied in both the first-pass and post-register branches. The ruling's "promoted-only" is superseded on this point.
- RunRegister rewiring: faithful port through registerTarget (meta construction verbatim; commitMeta errors now wrapped with "register <name>:" — an improvement, no regression); the single-guarded-register-path invariant is now literal code structure.
- recordApplyRefused: best-effort with a printed log line on failure — acceptable per the ruling; SQL matches the system_info genre, occurred_at DB-authoritative via clock_timestamp.
- The reshaped structural guard correctly encodes the stronger invariant (no raw INSERT + registerTarget + promoteExistingCandidate required).

After A1-A3: SHIP; AC#3's run oracle (next RC's poke within seconds of the cut) stands as ruled.
---
<!-- COMMENTS:END -->
