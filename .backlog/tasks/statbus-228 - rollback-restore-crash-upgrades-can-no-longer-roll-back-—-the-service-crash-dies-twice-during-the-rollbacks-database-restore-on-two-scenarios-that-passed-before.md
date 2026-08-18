---
id: STATBUS-228
title: >-
  rollback-restore-crash: upgrades can no longer roll back — the service
  crash-dies twice during the rollback's database restore, on two scenarios that
  passed before
status: To Do
assignee:
  - engineer
created_date: '2026-08-18 10:27'
updated_date: '2026-08-18 11:58'
labels:
  - upgrade-recovery
  - release
  - regression
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - tmp/operator-arc-fails34-triage-2026-08-18.md
priority: high
type: bug
ordinal: 228000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When an upgrade fails, the system's promise is that it rolls back: restore the database backup, restart the old version, leave a working box. At rc.03, that promise broke — and a release cannot ship while rollback is broken, because rollback is what makes every other upgrade risk survivable.

WHAT THE EVIDENCE SHOWS: two arc scenarios that exercise rollback (restore-broke-reattempt, jobs 95644094935; rollback-pair-terminal, 95644095093) both got through setup and into their rollback phase, then failed identically: "ROLLBACK_FAILED_DB_RESTORE: rollback could not complete — two consecutive crash-deaths during rollback (recovery attempt 1)", with the database connection dying mid-restore ("failed to receive message: unexpected EOF" on 127.0.0.1:3014). Both scenarios PASSED at the previous full suite (run 30755799405). The two failures are byte-identical in signature, 13-15 minutes into healthy runs — not the VM-starvation class (that one is 227).

THE SUSPECT WINDOW: everything between the last passing suite's commit and the rc.03 tag (bafcb396b) — which includes the recent restore/read-only-window work, the marker-truth rewrite on the restoration success arm, and the restore-identity changes. The crash-death-during-restore shape suggests the service process itself is dying while the restore runs (watchdog kill? panic? the restore's own connection handling?) — "two consecutive crash-deaths" is the budget guard's counting language, meaning the daemon died and its resume died again.

WHAT IS ACHIEVED BY FIXING: the promotion path reopens on a release whose rollback demonstrably works — the one property an unattended statistical-office box cannot live without.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Root cause traced with file:line — what in the suspect window makes the service crash-die during the rollback DB restore
- [x] #2 Fix designed (architect-reviewed) and landed with a RED-first oracle at the unit level where the mechanism allows
- [ ] #3 Both scenarios green at a suite run carrying the fix — the promotion candidate moves to that release
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-18 10:35
---
**ROOT CAUSE TRACED (AC#1). VERDICT: PRODUCT BUG, not scenario drift. Two defects, both from 21ec09911 (STATBUS-197, 2026-08-16) — verified an ancestor of rc.03 (bafcb396b). Full trace: tmp/engineer-228-trace-2026-08-18.md. No fix designed — architect's diagnosis gate first.**

**THE SERVICE NEVER CRASHED UNEXPECTEDLY.** Both arcs INJECT the deaths they report: "two consecutive crash-deaths during rollback" is the product's own designed terminal for the `(rollback, rollback)` step pair these arcs engineer on purpose, and each kill marker was verified consumed by the arc itself. The `unexpected EOF` is not a crash either — it is a connect attempt against a database the product deliberately stopped one second earlier. No SIGABRT, no panic text anywhere in either 400KB log; the triage's three hypotheses are refuted.

**WHAT ACTUALLY FAILED — one assertion each, same upstream fact:** rollback-pair-terminal — `recovery_attempts=3` not confirmed (log 4965); restore-broke-reattempt — the STATBUS-111 re-attempt legend never printed (log 4568), because `StateRestoreReattemptable` needs `state='failed' AND backup_path IS NOT NULL` (service.go:3761, :8247) and the row shows `"backup_path": null` (log 4921).

**DEFECT 1 — the row's backup_path write targets a STOPPED database. Deterministic: every upgrade, every box.** :5587-5588 stops the DB (hard step — "rsync of a running Postgres data dir is NOT crash-consistent"); :5618 takes the cold backup; then **:5638** runs `terminalExec("UPDATE public.upgrade SET backup_path = …")` against that stopped server:
```
M 10:17:51 Stopping database… / Container statbus-test-db Stopped
M 10:17:52 Backing up database…
M 10:18:00 Warning: could not record backup_path … failed to connect … unexpected EOF
```
`terminalExec` (:7959) is teardown-immune against a dying CONNECTION (154/163) — it opens a fresh one. It cannot conjure a stopped SERVER. 197 moved this write here; it previously ran early as intent via `d.queryConn.Exec` with a ping/reconnect, while the DB was up.

**BLAST RADIUS EXCEEDS THE TWO ARCS.** A later write at :6402 sets backup_path once the forward path reconnects — so a SUCCESSFUL upgrade looks fine. The column is NULL exactly when the upgrade dies before that point: the crash/rollback population STATBUS-111 exists for. **`./sb install` can no longer re-attempt a failed restore on any box**, and the pending probe at :3761 counts zero forever. The comment at :5627-5637 claims both carriers hold the identity and "backup_path == '' ⇔ nothing moved" is exact — one carrier is structurally dead, and the invariant now reads FALSE in the dangerous direction.

**DEFECT 2 — a PreSwap flag now carries a BackupPath, falsifying the recovery branch's premise.** 197 stamps the FLAG at the same moment (:5641) with the phase UNCHANGED — its own comment says "still old-sb-upgrading" (:5634-5635). The PreSwap branch is built on the opposite: ":1315-1318 — a PreSwap flag carries an empty BackupPath … restoreDatabase refuses to touch the volume"; ":1348-1349 — empty by construction at PreSwap". Both now false. Observable: the branch prints "The database was not modified, so nothing needs restoring … no snapshot recorded" (:1342, log 10:18:25), then twelve seconds later logs `Restoring database from backup at …/pre-upgrade-active` (log 4855, 4896). A PreSwap rollback that was a database no-op is now a full destructive restore cycle — data-neutral in content, but a large new failure surface on exactly the path these arcs kill into.

**WHY THIS IS NOT SCENARIO DRIFT.** rollback-pair-terminal's header states the invariant in the product's own words: "the DB COLUMN backup_path is set during the very first dispatch's backup step … independent of flag.BackupPath, **which IS empty on this route**". The scenarios assert what the product's comments STILL claim; the product changed underneath its own documentation.

**ONE THREAD NOT FULLY TRACED, flagged not guessed:** `recovery_attempts=1` vs 3. The pair-terminal fired correctly (it keys on the on-disk step pair the arc verified formed). The count is second-order — recovery now routes through the PreSwap "nothing changed" branch rather than the counted path the choreography assumed. Needs one more pass; changes neither root cause nor fix shape.

**FIX SHAPE for the ruling (not implemented):** (1) the row write must happen where the DB is reachable — my read: make the existing post-reconnect write at :6402 the single row recorder, letting the FLAG carry the identity across the DB-down gap; (2) the PreSwap premise must be restored (flag stamp moves past the swap boundary) or :1300-1353's argument and message rewritten for a world where a PreSwap flag carries a snapshot identity — a semantics call. RED-first oracle without a VM: a source pin that no `public.upgrade` row write sits between the `stop db` step and the DB restart in `executeUpgrade`.
---

author: engineer
created: 2026-08-18 10:37
---
**RE-TESTED AGAINST THE ARCHITECT'S THREE-PART STANDARD. Defect 1 stands as a regression. Defect 2 I had mis-filed — it is his THIRD FORK, and I am re-routing it to him rather than forcing it into my own boxes.** Addendum appended to tmp/engineer-228-trace-2026-08-18.md.

**His two grounded facts, verified here rather than taken on report:**
- `git log --name-only 21ec09911..bafcb396b -- test/install-recovery/{arcs,scenarios}/` → EMPTY; 197 itself touched neither. Assertions are unchanged across the whole window.
- 209 (8b58e533c) is topically restore-adjacent but refuted as a cause by the evidence: the failing connect targets a DELIBERATELY STOPPED container, and read-only residue produces permission errors, not a connect EOF. It survives only as a candidate for the untraced attempts-count thread.

**DEFECT 1 — fails test (c) decisively ⇒ REGRESSION.** (a) holds (21ec09911 with 197's "record at commit, never as intent" ruling); (b) holds (the arcs assert the row-keyed STATBUS-111 re-attempt); **(c) FAILS**: `backup_path` is NULL on every crash/rollback row, the human-gated replay is dead fleet-wide, and the row asserts "nothing moved" while a snapshot exists. 197's own comment (:5627-5637) claims BOTH carriers hold the identity — the shipped behaviour contradicts the ruling it shipped under. Different AND wrong.

**DEFECT 2 — THIRD FORK: deliberate change, VM-level consequence never ruled.** Re-tested honestly it is not the same animal:
- (a) **partial.** The stamp move is deliberate and ruled. Whether a PreSwap rollback should now RESTORE was never ruled — and there is mechanical evidence it was never considered: `git log -L 1341,1353:cli/internal/upgrade/service.go` shows the branch's "flag.BackupPath is empty by construction" premise was last touched **77fa16fb2, 2026-07-14**, a month BEFORE 197 made it false. Nobody revisited the branch whose safety argument 197 invalidated.
- (b) holds — the arc header encodes the old contract verbatim.
- (c) fails, but on narrower ground than Defect 1. The restore itself is data-neutral (the snapshot came off the unchanged volume moments earlier — **my reasoning, not an observation**; flagged for adversarial check). What is unambiguously wrong is the contradiction: the branch prints "the database was not modified, so nothing needs restoring" WHILE restoring.

So Defect 2 splits, and only the second half is mine:
1. **Unambiguous defect:** the product states an invariant that is false. Either the code or the comment must move — not a design question.
2. **Genuinely unruled design question → architect:** what SHOULD a PreSwap rollback do now that a PreSwap flag legitimately carries this attempt's snapshot identity — restore it (current behaviour; the message must then change) or refuse as before (the stamp moves back past the swap boundary)? And in his framing: what should a rollback scenario OBSERVE when it does? I am not forcing this into "fix" or "test edit".

**PROCESS FINDING, recorded as asked — not used as a free pass.** 197 invalidated a premise another function's safety argument rests on, and no review caught it. The miss is mechanically detectable: the invalidated claim states itself IN WORDS ("empty by construction at PreSwap") a dozen lines from the code that made it false, and had sat untouched since July. Cheap guard for the class: when a change alters WHEN a field is populated, grep the field name in COMMENTS, not only in code — every statement about a field's lifecycle is a premise some other branch may be standing on.
---

author: architect
created: 2026-08-18 10:39
---
DIAGNOSIS REVIEW, PART 1 — CONFIRMED AND SHARPENED. Product bug, not scenario drift, not the third fork. Verified at source, not accepted from the trace. Both defects are real; ONE IS WORSE THAN STATED, and the OTHER's severity claim is REFUTED by evidence already inside this trace.

DEFECT 1 — CONFIRMED, AND WORSE. The code says it out loud: the comment at :5629-5633 justifies terminalExec because "queryConn was closed for the consistent backup" — which CONFLATES the daemon's own connection being closed with the POSTGRES SERVER being stopped. Step 4 (:5588) runs `docker compose stop db`. terminalExec (:7959) delegates to terminalConnDo and runs `conn.Exec` on a FRESH connection: teardown-immune against our own connection dying, useless against a server that is not running. The :5638 write therefore fails on EVERY upgrade, deterministically, masked on successful ones by the post-reconnect write at :6402.

THE UNDERSTATEMENT: the consequence is not only that STATBUS-111's human-gated replay is dead and the :3761 probe counts zero. That probe IS STATBUS-209 ARM A's abort-hold guard — `SELECT COUNT(*) ... state='failed' AND backup_path IS NOT NULL` — whose own comment says the git-restore-fail ABORT "deliberately holds read-only on a broken volume until that replay — this backstop must NOT strip that protection early". With backup_path NULL fleet-wide, that guard reads zero and FAILS OPEN: the read-only hold protecting a broken volume is stripped early, on exactly the population it exists for. Defect 1 does not merely disable the replay path — it disables the safety hold the replay path depends on. That belongs in the fix's commit message.

DEFECT 2 — CONFIRMED, AND THE "DATA-NEUTRAL IN CONTENT" READING IS REFUTED. The premise 197 falsified is stated twice (:1315-1318, :1348-1349): "flag.BackupPath is empty by construction at PreSwap". A PreSwap flag can now carry one, so restoreDatabase no longer refuses and a database no-op became a full restore cycle. He flagged this as alarming-but-content-neutral and asked me to attack it. It does not survive.

HIS OWN FLAGGED-NOT-TRACED OBSERVATION IS THE REFUTATION. recovery_attempts read 1 where 3 was expected. That is neither second-order nor unexplained: writeRollbackTerminal's contract documents this exact hazard at :7979-7985 — "a volume-rewind restore (restoreDatabase) REVERTS THE COLUMN to whatever the pre-upgrade snapshot had (typically 0), and this UPDATE is what runs AFTER that rewind, so every updateSQL string MUST include recovery_attempts = $2 or the re-impose is a silent no-op." A restore that now runs where it never ran before rewinds the counter. The observed 1-vs-3 IS that volume rewind, predicted by the codebase's own comment. So the restore is demonstrably NOT content-neutral: it rewinds at least one column the recovery budget depends on — and recovery_attempts is what decides park-versus-continue.

SECOND, INDEPENDENT REASON the neutrality claim fails: even where content happened to match, the PreSwap path's SAFETY no longer comes from its invariant. The STATBUS-039/-031 argument is that an unrecorded snapshot makes restoreDatabase REFUSE, and that refusal is what prevents restoring another upgrade's months-old backup over an untouched volume. It is now bypassed. Today the stamped path happens to be this attempt's own snapshot, so the outcome is right — but right by luck about which path got stamped, not by the invariant the code relies on. A safety property that holds by coincidence is not a safety property.
---

author: architect
created: 2026-08-18 10:39
---
DIAGNOSIS REVIEW, PART 2 — THE RULINGS.

FIRST, ON HIS RE-ROUTING (comment #2): re-testing his own verdict against the standard and MOVING Defect 2 out of his boxes into the third fork was the right call, and the `git log -L` evidence — the invalidated premise last touched 2026-07-14, a month before 197 made it false — is exactly the kind of mechanical proof that turns "nobody thought about it" from an assumption into a finding. But the split he proposes does not survive my part-1 refutation. He kept half of Defect 2 as an unruled design question on the grounds that the restore is data-neutral. It is not. The recovery_attempts rewind makes the current behaviour WRONG, not merely undocumented — so this is not an open question about what we would prefer. There is only one admissible answer.

RULING ON THE SEMANTICS QUESTION HE ROUTED TO ME — RESTORE THE PREMISE. The flag stamp moves back past the swap boundary; a PreSwap flag carries an empty BackupPath again; the branch's message and its safety argument stand unchanged because they become true again. Do NOT rewrite :1300-1353 for a world where PreSwap carries a snapshot identity. Four reasons:
1. The current behaviour is wrong, not just undocumented — it rewinds recovery_attempts, and that column decides park-versus-continue.
2. Rewriting the argument means re-proving a WEAKER safety property across every PreSwap path, and part 1 shows the weaker property is already false.
3. Stamping at PreSwap contradicts 197's OWN goal. Its invariant is "backup_path == '' ⇔ nothing moved". At PreSwap, nothing HAS moved — that is the definition of the phase. So the stamp there asserts the opposite of what 197 set out to guarantee.
4. 197's stated worry was that destructive steps might precede the stamp. For a PreSwap flag none do: the recovery-boot target checkout is gated on IsServiceNewSbRecovery() (forward phases only), which excludes PreSwap. THE BUILDER MUST VERIFY THAT PREMISE HOLDS FOR EVERY PHASE TRANSITION — it is what this ruling rests on, and I want it checked rather than inherited from me.

FIX SHAPE (1) — POST-RECONNECT ROW WRITE: APPROVED, and it is not a retreat from 197's doctrine but the only implementable form of it. No row write can land while the server is stopped, so "record on the row at commit" was never achievable in that window on that carrier; the first instant the server is reachable IS the earliest honest record. Two conditions: it must be the FIRST write after reconnect, before anything else can fail; and the FLAG stays the authoritative carrier across the DB-down gap, which it already is. With the stamp moved back per the ruling above, the two carriers become honest at different moments by design — flag at the swap, row at reconnect — and the comment must say so instead of claiming both record at one commit point.

ORACLES — his RED-first pair is right and sufficient to land without a VM. The source pin that no upgrade-row write sits between stop-db and DB restart; and the behavioural arm running terminalExec against a STOPPED SERVER, not a closed connection — that distinction IS the defect, and a test that only closes a connection would pass against the broken code. ADD TWO:
• a PreSwap flag carries an EMPTY BackupPath — the invariant being restored, and the one a future edit would silently break again;
• an arm proving the restore no longer runs on the PreSwap path, since "prints nothing needs restoring, then restores" is the observable that exposed this.

THE UNTRACED THREAD IS NOW TRACED — close it rather than carrying it. recovery_attempts 1-vs-3 is not second-order and needs no further pass: it is the volume rewind documented at :7979-7985, caused by Defect 2's newly-occurring restore. It should disappear when the premise is restored, and that disappearance is a free confirmation of the fix. If it does NOT disappear, something else is also wrong and we want to know loudly — so assert it, do not merely expect it.

EVIDENCE GAP WORTH CLOSING CHEAPLY: the single-suspect conclusion rests on ancestry established locally via merge-base, because the sandbox could not reach the GitHub API. Have the operator pull the previous green suite's run head_sha and confirm 21ec09911 is absent from it — seconds of work, and it converts "single suspect" into "single suspect, confirmed against the last green".

HIS PROCESS FINDING — ACCEPTED, AND IT IS MINE TOO. 197 invalidated a premise another function's safety argument stands on, and no review caught it, including mine. His proposed guard is right and I would state it as a rule: WHEN A CHANGE ALTERS WHEN A FIELD IS POPULATED, GREP THE FIELD NAME IN COMMENTS, NOT ONLY IN CODE — every statement about a field's lifecycle is a premise some other branch may be standing on. Worth carrying into the role docs beside the gofmt step; both came from the same week of near-misses.
---

author: engineer
created: 2026-08-18 10:47
---
**BUILT to the ruling, FROZEN for review (no commit).** Files: `cli/internal/upgrade/service.go`, new `cli/internal/upgrade/backup_path_carriers_test.go`, and an AMENDED 197 test (flagged below — do not miss it). AC#1 closed; AC#2's code is here; AC#3 rides the next suite.

**DEFECT 1** — the `:5638` row write is GONE. The post-reconnect write in `applyNewSbUpgrading` is now the SINGLE row recorder and is already the first write after "Database reconnected.", as ruled; its comment says why that is the earliest honest instant (the server is stopped from Step 4 through the swap) and names both readers it exists for — STATBUS-111's replay AND the `:3761` abort-hold guard that FAILS OPEN on a NULL column, stripping the read-only hold protecting a broken volume. That goes in the commit message as sharpened.

**DEFECT 2** — the `mutateHeldFlag` stamp at `:5641` is GONE. The flag gains its identity only at `updateFlagNewSbSwapped(backupPath)`, so "empty by construction at PreSwap" is TRUE again and `:1300-1353` stands unchanged. I did not rewrite the data-safety argument.

The carrier comment now says the two become honest at DIFFERENT moments BY DESIGN — flag at the swap, row at reconnect — rather than claiming one commit point.

**MANDATORY VERIFICATION — PHASE-TRANSITION SWEEP. The premise HOLDS, positively.** Every operation between `backupDatabase` and the moved stamp: `git branch -f pre-upgrade` (a ref); `fetchWithStallDetection` (objects only — checkout deferred by STATBUS-060); manifest verification (read-only); `replaceBinaryOnDisk`. **No DB-mutating step and no working-tree checkout precede the stamp.** At every crash point before it the volume is byte-unchanged — so an EMPTY BackupPath is the CORRECT value and `restoreDatabase`'s refusal is right, not a gap.

One window named honestly: between `replaceBinaryOnDisk` and the stamp the binary is swapped while the flag still reads PreSwap. PRE-EXISTING (pre-197), and exactly what the C5 `killed-by-system-during-binary-swap` inject exercises — the rollback-pair-terminal arc's own 1st dispatch. The DB is untouched there too, so empty stays correct.

Forward transitions:
- `IsServiceNewSbRecovery` (`:415-420`) requires Phase ∈ {NewSbSwapped, NewSbUpgrading} — PreSwap excluded IN THE PREDICATE, used by both checkout gates (`:1974`, runCrashRecovery). **Your premise verified at source, not inherited.**
- NewSbSwapped → NewSbUpgrading carries `BackupPath: flag.BackupPath` (`:7567`).
- The ROW's write point (first reconnect) precedes the first DB-mutating step (migrate up) — each carrier is written before the first mutation its readers care about; the two rules compose.
- Flags synthesized from the row (`:3103`, `:3155`) get an empty BackupPath in the pre-reconnect crash population — correct, nothing has moved yet.

**ORACLES — honest status per arm:**
- **Source pin** (no `public.upgrade` write between the Step-4 stop and the swap handoff): **RED-verified** — restoring 197's write fails it, naming the offending line.
- **PreSwap flag carries an EMPTY BackupPath**: **RED-verified** — restoring 197's stamp fails it.
- **`terminalExec` against a STOPPED SERVER** (a real listener bound then closed, so the port is genuinely dead — not a closed connection): passes in BOTH states **by design**. It is a PREMISE pin, not a defect detector — it proves the fact that justifies removing the write. Calling it RED-first would be false.
- **PreSwap does not restore**: premise/observable pin — the branch's message and its "empty by construction" claim must both still exist, and `restoreDatabase`'s empty-path refusal must be its FIRST act. Also not RED-first.
- **recovery_attempts == 3**: nothing added — already asserted loudly at VM level (rollback-pair-terminal:277, `after 3 attempt(s)`), and the `recovery_attempts = $2` re-impose is already pinned (rollback_terminal_write_test.go:60). It closes at AC#3's run; if it does not come back, the arc says so.

**FLAGGED — I AMENDED A TEST ANOTHER TICKET LANDED.** `TestExecuteUpgrade_BackupPathRecordedAtCommit_STATBUS197` pinned the exact behaviour this ruling removes, and failed — correctly. I did not delete it: renamed to `..._BackupPathNeverRecordedAsEarlyIntent_STATBUS197`, keeping 197's SURVIVING invariant (identity never recorded before the snapshot commits — both new write points still satisfy it), with the 228 amendment written into its header. Please review that edit specifically.

**Verification:** `go test ./...` in cli/ — 12 packages ok, 0 failures. `gofmt -l` clean. `golangci-lint run ./...` 2.12.2 — 0 issues.

**Still open (your cheap evidence gap):** the operator pulls the previous green suite's run head_sha to confirm 21ec09911 is absent — my sandbox cannot reach the GitHub API.
---

author: foreman
created: 2026-08-18 10:47
---
SUSPECT CONFIRMED AGAINST THE LAST GREEN SUITE. Operator evidence: run 30755799405 (the last green full suite) ran at head 2ab6126a1c3b, 2026-08-02; merge-base confirms 21ec09911 is ABSENT from that commit — and it IS an ancestor of rc.03 (bafcb396b, established earlier). CORRECTED INTERPRETATION for the record (the operator's report read this backwards): absent-from-green + present-in-failing is the CONFIRMATION — the scenarios passed without the suspect commit and fail with it. "Single suspect" is upgraded to "confirmed against the last green", as the architect's ask intended. Build proceeding on both defects per comments #3/#4.
---

author: architect
created: 2026-08-18 10:50
---
FIX REVIEW — APPROVED, no amendment. Both rulings realized, and the result is structurally stronger than what I ruled. Verified at source rather than accepted from the freeze report.

THE INVARIANT BECAME STRUCTURAL, WHICH IS BETTER THAN THE RULING ASKED FOR. I ruled "move the stamp back past the swap boundary" and expected a documented convention. updateFlagNewSbSwapped sets `flag.Phase = PhaseNewSbSwapped` AND `flag.BackupPath = backupPath` in the SAME write (:633-634). So "PreSwap ⇒ empty BackupPath" is no longer something anyone must remember — it is enforced by there being exactly ONE writer of BackupPath, and that writer also flips the phase away from PreSwap in the same breath. The premise cannot be falsified again without deliberately splitting those two assignments. NAME THAT COUPLING IN A COMMENT AT :633-634 so a future refactor does not separate them for tidiness — it is now load-bearing, and nothing there says so.

SINGLE-RECORDER CLAIM VERIFIED LITERALLY: `SET backup_path` appears exactly ONCE in service.go, at :6431. Not "the intended single recorder" — the only one.

THE RESIDUAL I WENT LOOKING FOR IS NOT THERE. I checked whether the [swap → reconnect] window can strand a 'failed'-with-retained-backup row (flag has the identity, row still NULL) and so miss STATBUS-111 anyway. It cannot: the post-reconnect write precedes migrations and the health check, so any post-swap failure that routes to rollback occurs AFTER the row is recorded; and a failure BEFORE it means the database never came back, in which case no design could write the row at all. The row is NULL exactly when the database is down — which is precisely why the flag is authoritative across the gap. The fix is complete rather than partial, and that is worth stating because "the flag covers the gap" reads like a concession until you check that the gap is unwritable by anyone.

(1) THE AMENDED TEST — APPROVED, and it STRENGTHENS the pin rather than relaxing it. The test for a legitimate test amendment: does it preserve the INVARIANT the original protected, or relax the ASSERTION to match new behaviour? This one generalises. The original pinned "backup_path is written at the commit moment"; the amendment pins "executeUpgrade contains NO backup_path row write at all", which refuses BOTH 197's bug (early intent) and 228's bug (a write into the server-stopped window) with one rule. 197's surviving ordering invariant is kept explicitly (:82-84, flag stamp must not precede backupDatabase), and a new assertion pins my ruling's mechanism (:78-80, the flag gains its identity at the swap). The header states what changed and why the original form was unimplementable. This is how a landed pin should be amended.

(2) THE TWO PREMISE PINS — ACCEPTABLE HERE, and I want the reason narrow so it does not become a licence. A premise pin is legitimate when it asserts a FACT THE DESIGN DEPENDS ON and would fail if that fact changed — the stopped-server terminalExec arm qualifies exactly: if someone later makes terminalExec retry until a server returns, that arm goes red and tells us the removal's justification has evaporated. It is NOT a substitute for a regression pin, and it is only acceptable because the regression proof is carried elsewhere and RED-verified: the source pin and the empty-BackupPath pin. Had those two been premise pins too, I would have refused the unit. Saying so plainly instead of presenting four equal arms is the right instinct.

(3) recovery_attempts==3 — VM-LEVEL ASSERTION SATISFIES "assert, don't expect". My concern was that the thread would be carried as an unexplained expectation; it is now explained (the volume rewind) and asserted where it is observable, with the re-impose pinned at unit level. A unit arm would have to simulate a restore's volume rewind — synthetic, and it would pin the simulation rather than the behaviour. ONE CONDITION: the commit message must say the confirmation RIDES AC#3's run, so nobody reads the landing as the proof.

ANCESTRY CONFIRMATION (foreman comment #6) closes the evidence gap — suspect absent from the last green's head, present at rc.03. "Single suspect" is now single suspect, confirmed.
---

author: architect
created: 2026-08-18 10:51
---
RE-FREEZE ADDENDUM — VERDICT UNCHANGED, STILL APPROVED. My comment #7 was written against the frozen state and none of the three additions disturbs it; the footprint correction changes nothing either — I read the amended pin in claim_window_stale_pin_test.go directly, which is where I found it.

(1) LOCAL BIDIRECTIONAL ANCESTRY: good, and better than the ask. I requested one direction (suspect absent from the last green). Verifying BOTH ends locally establishes 21ec09911 as the one commit distinguishing green from red without depending on an API the sandbox cannot reach — the conclusion no longer rests on a tool that was unavailable when it mattered.

(2) THE GUARD APPLIED TO ITSELF: correct, and his reasoning is the sharper statement of my own ruling. I said prose is not a mechanism; he noticed that my ruling was ALSO prose until it was written at the point where the deletion would happen. A test whose whole job is to assert what some comments claim looks exactly like a redundant test to a future tidier — so the header saying THIS TEST IS THE MECHANISM is what keeps the mechanism alive. That is the principle eating its own dogfood, and it is right.

(3) THE LINT FALSE-GREEN — THE MOST IMPORTANT LINE IN THE RE-FREEZE, AND IT IS NOT ABOUT THIS UNIT. golangci-lint run from the repo root errored on module resolution AND STILL PRINTED "0 issues". He caught it and re-ran from cli/, so this unit's chain is genuinely green. But the tool that gated EVERY unit in this campaign can report a clean result while having analysed nothing, and the only thing standing between that and a false pass was one builder noticing an error line above the summary.

THAT IS THE FIFTH INSTANCE OF ONE CLASS TODAY, and naming the class is worth more than the five tickets: a run concluding SUCCESS with zero scenario jobs (215); a gate printing "✓ FULL SUITE green (0/0 arc jobs present)" against an empty domain (216); a trigger pin satisfied by a COMMENT containing the string it grepped for (224); an exempt-ride that would have refused every real board commit while every test passed, because the fixtures used ASCII filenames and real ticket names do not (219); and now a linter reporting zero issues over zero analysed packages.

They are one shape: A GREEN SIGNAL PRODUCED BY A CHECK THAT NEVER EXAMINED THE THING IT CLAIMS TO HAVE EXAMINED. And one rule catches all five: A CHECK MUST REPORT WHAT IT EXAMINED, AND A ZERO-SCOPE EXAMINATION MUST BE A FAILURE RATHER THAN A PASS. Zero jobs, zero required arcs, zero code lines behind a matched string, zero realistic fixtures, zero analysed packages — every one of today's five is that rule violated in a different costume. I am taking the doctrine write-up and the lint case as my own next items rather than adding them to this unit.

NOTHING FURTHER ON 228. Commit with the coupling comment at :633-634 folded in and the rides-AC#3 line in the message, both from comment #7.
---

author: foreman
created: 2026-08-18 10:51
---
LANDED at a20a416a3, architect-approved with no amendment (verdict comment #7): both defects fixed, the landed shape structurally STRONGER than the ruling (one writer sets BackupPath and flips the phase in the same write — the coupling now commented as load-bearing at his comment-only fold), the single-recorder claim verified literally (SET backup_path appears exactly once), the swap-to-reconnect residual hunted and proven unwritable-by-anyone, and the amended 197 pin judged a strengthening (generalizes to "no row write in executeUpgrade at all"). AC#1 and AC#2 closed. AC#3 (both scenarios green at a suite carrying the fix) rides the King's next cut — the promotion candidate moves to that release. Commit message carries the fail-open sharpening, the ancestry confirmation, and the AC#3-rides note as conditioned.
---

author: architect
created: 2026-08-18 11:58
---
PIN GAP — YES, EXTEND IT INDEPENDENTLY, and the reason is today's own doctrine turned on my own ruling. I designated TestPreSwapFlagCarriesNoBackupPath_STATBUS228 as THE MECHANISM for the invariant "a PreSwap flag carries no BackupPath". It is a SOURCE PIN OVER executeUpgrade. So it examines ONE FUNCTION and claims a property of THE FLAG — scope narrower than the claim, which is exactly the zero-scope shape doc-033 names, in its sixth costume. STATBUS-210's rewrite is a second runtime producer of the forbidden state (:6002-6008, "BackupPath KEPT"), and the 229 log is the proof that it bites: the restore the invariant exists to prevent actually ran at 10:32:58. The engineer found this in his own fix, which is the right instinct and the finding I should have made when I designated the pin.

MY 229 RULING REMOVES THE SECOND PRODUCER — 210 stops blanking the Phase, so Phase stays new-sb-swapped and the PreSwap+BackupPath combination cannot arise there. But the pin must STILL be extended, because a fix that removes today's second producer says nothing about tomorrow's third. The invariant is about the FLAG, so the pin must be about the flag: assert over every writer, not over one function. Cheapest sound form is a source pin covering EVERY mutateHeldFlag / flag-writing call site that touches Phase or BackupPath, with the assertion stated as the flag-level rule; better still if it can be expressed as a unit over the flag value itself. Whoever builds 229 folds it in — the two belong together, since 229 is the change that makes the invariant true again and the pin is what keeps it true.

No change to 228's verdict: the fix is correct and correctly landed. The pin was under-scoped, which is a separate defect in the mechanism rather than in the code it guards.
---
<!-- COMMENTS:END -->
