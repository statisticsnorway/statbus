---
id: STATBUS-452
title: >-
  installer overtakes an orphaned in_progress row; the new daemon's flagless
  recovery then marks that older version completed, so the ledger and footer
  report the wrong running version
status: In Progress
assignee: []
created_date: '2026-10-06 08:45'
labels:
  - upgrade
  - install
  - ledger
dependencies: []
references:
  - STATBUS-436
  - STATBUS-447
  - STATBUS-442
  - STATBUS-039
priority: high
---

## Status: OWNER DECIDED 2026-10-06 09:24 UTC: A + B + C in rc.17, then D happens by deploying rc.17 to demo. Norway waits for rc.17. Work is delegated (coordinator does not implement).

## Zoom out

On 2026-10-06 at 08:29:50 UTC the owner ran `./cloud.sh install demo v2026.10.0-rc.16`. Demo is repaired in substance:
- binary, HEAD, the resident daemon's executable and all containers are rc.16 `7e92d115`
- the maintenance flag is absent
- the false v2026.09.3 loop stopped: no activity on row 25829 after 08:30:57
- the legacy secrets moved to `.env.credentials`
- unit NRestarts 0

The ledger is wrong, though. Row 25829 (v2026.09.3) ended `completed` at 08:30:57, eight seconds after rc.16's own row (227493, completed 08:30:49). As a result:
1. The site footer shows "Statbus version v2026.09.3 (ebe058af)". It reads `public.running_identity()`, which returns the latest `completed` row by `completed_at`.
2. `/admin/upgrades` "Currently running" shows rc.16 (`history.find(u => u.state === "completed")`, a different ordering). The two views disagree.
3. The new daemon fired the success callback (`UPGRADE_CALLBACK=./ops/notify-slack.sh`) for "Upgrade to v2026.09.3 complete". A false Slack message was probably sent; not yet verified.
4. The next install's row gets `from_commit_version` from the latest completed row (`cli/cmd/install.go:3554`), so it would say "from v2026.09.3".

## Zoom in: timeline (demo journal, upgrade_state_log, install log)

- 08:29:54: the old v2026.09.2 daemon (PID 3288378) claims row 25829 again. `install.sh` prints "Waiting for the upgrade mutex — another party holds it", then "Upgrade mutex acquired; continuing". The 447 handoff waited and never killed anything, as designed.
- 08:30:16: the db container is recreated (step 10 "Apply config changes": db, worker, app and proxy recreated).
- 08:30:23–08:30:29: the old daemon keeps looping (state-log rows 801715–801726: claim, fail, reschedule).
- 08:30:29.486: its last claim, scheduled → in_progress (row 801727). It is refused with "another ./sb install is already running (install, invoked_by=install.sh:statbus_demo)", which is correct (447).
- 08:30:30: "Database connection lost". **Its `failed` write never lands**, so the row stays `in_progress`. It logs "removeUpgradeFlag: upgrade flock held by another live actor — leaving the flag file in place".
- 08:30:49: the installer records rc.16 row 227493 `completed`. The install output has **no "Superseded" line**: `upgrade_supersede_older` only touches `available`, `scheduled`, `failed` and `rolled_back`, never `in_progress`.
- 08:30:50: the unit restarts on rc.16 (PID 3639343).
- 08:30:55: the new daemon's boot runs `completeInProgressUpgrade` (flagless recovery) and logs "Service restarted. Found in-progress upgrade to v2026.09.3, verifying...".
  - `verifyUpgradeObservedStateEx` says the binary 7e92d115 is a **descendant** of 09.3 ebe058af (`git merge-base --is-ancestor`) and all migrations are applied, so the row counts as at target (`ObservedAlreadyAtNew`).
  - The health check passes.
- 08:30:57: row 25829 is set `completed` ("upgrade row [completed-from-in-progress]"), `runUpgradeCallback` fires, and the daemon logs "Upgrade to v2026.09.3 complete (verified serving after flagless recovery)."

## Defects (three, layered)

1. **Installer leaves an orphaned older `in_progress` row behind.** While the installer holds the upgrade mutex, no other row can legitimately be `in_progress`, so any such row is orphaned (its claimant lost the race or died). The installer's post-install supersede skips it.
2. **Flagless boot recovery completes an overtaken row.** Treating "binary is at or after the target" as "this row's upgrade finished" is deliberate (STATBUS-039) for a crash after the binary swap. It is wrong when a different, newer install completed in between: rc.16's row completed at 08:30:49, after 25829's last claim at 08:30:29. Recovery marks the older row completed and announces it.
3. **"Which version is running" has no single source of truth.** `running_identity()` takes the latest `completed_at`. The upgrades page uses a different order. Whichever row completed last wins, not the version actually running.

## Why the rehearsal passed and demo did not

In the rc.16 operator rehearsal, the old daemon's refusal was recorded as `failed` and the installer then superseded it. On demo, the old daemon's last claim landed just before its DB connection was cut, so `failed` was never written. This is timing-dependent. What cut the connection at 08:30:30 is **not yet verified**. Candidates: step 12 "Database sessions" (`cleanOrphanSessions` / `pg_terminate_backend`), or the traffic pause before Migrations.

## Options (owner to choose; they can combine)

- **A. Recovery side:** in flagless recovery, if a newer `completed` row exists that the running binary belongs to, mark the stale row `superseded`, not `completed`, and fire no success callback. This fixes defect 2.
- **B. Installer side:** after recording its own completed row, while still holding the mutex, also supersede older `in_progress` rows. They cannot be live because the installer holds the mutex. Needs the transition guard (`upgrade_guard_operator_transitions`) to permit `in_progress → superseded` for the install actor. This fixes defect 1 at the source.
- **C. Display:** derive the running version from the actually running commit (for example, the row whose `commit_sha` equals the installed binary or HEAD), not from `completed_at` order, and use one selector for the footer and the upgrades page. This fixes defect 3.
- **D. Demo's existing bad row:** repair it through the fixed software, for example a ledger-repair step in the next install, not hand-written SQL. A forward repair must also be correct for any box that hit this.

The agent's recommendation is A + B (both ends of the race), and C as its own decision, then D through the release that carries them.

## Investigation findings (buffalo, gpt-6.1-sol xhigh, read-only, 2026-10-06 08:53; full report `tmp/452-investigation.md`)

- **Q1, what cut the old daemon's connection:** most likely step 10 recreating the **proxy**, not the "Database sessions" cleanup or the migration pause.
  - The proxy container was Created at 08:30:29.934 and Started at 08:30:31.251. That overlaps the old daemon's last claim (08:30:29.486, which landed) and its lost `failed` write.
  - The DB had been ready since 08:30:18. `pg_stat_database.sessions_killed = 0`.
  - Status: strong inference. The exact socket close is not recorded.
- **Q2, the false notification:** the callback ran successfully (exit 0) with `STATBUS_EVENT=completed` for v2026.09.3. **CONFIRMED DELIVERED (owner's Slack screenshot, 2026-10-06 09:22 UTC):** "The Workspace Reporter" posted at 10:30 local (08:30 UTC): "Upgraded **niue** from `v2026.10.0-rc.16` to `v2026.09.3` — https://demo.statbus.org". It reads as a **downgrade** of demo, which is false: demo runs rc.16. The "from" value is rc.16 because that was the latest completed row at the moment of the callback.
- **Q3, every reader of "running version":**
  - Reads v2026.09.3 now:
    - `public.running_identity()` (`completed_at DESC`), and through it the app footer (its only consumer)
    - the next install's `from_commit_version` (`install.go:3554`, `completed_at DESC`, no tie-break)
    - the admin stale-install-failure banner cutoff (`page.tsx:243-258`, 08:30:57)
  - Reads rc.16 now: `/admin/upgrades` "Currently running", which orders by `committed_at DESC` and is a different selector.
  - Readers based on the binary or HEAD are unaffected.
- **Q4, the transition guard:** it already allows unparked `in_progress → superseded`, with or without an operator actor. The only thing that excluded row 25829 is `upgrade_supersede_older`'s state filter (`available`, `scheduled`, `failed`, `rolled_back`).
- **Q5, why the rehearsal differed, and exposure:**
  - The operator rehearsal avoided the lost-write window: the refusal was persisted, then superseded. It also accepted rc.16's own row ending `superseded`, so it never proved the running-version ledger correct (a test gap).
  - The service path alone cannot produce two in_progress rows (partial UNIQUE index `upgrade_single_in_progress`).
  - **Norway (healthy v2026.09.3 daemon, `./sb upgrade schedule`) is not expected to hit this.** It is a one-row pipeline, and 09.3 has the pre-claim flock check. This is a source-based conditional conclusion, not a live rune run.
  - The recovery bug can still be reached by any daemon that finds a stale in_progress row after an independent newer install completed. That needs a box with an old looping or crashed claimant plus an operator install, as demo had.
- **Q6, predicate candidates for "overtaken, not finished" (sketches; r is the stale in_progress row, c is a different completed row):**
  - **P1:**
    - `r.commit_sha != binaryCommit`
    - AND a completed c exists with `c.commit_sha == binaryCommit` AND `c.completed_at > r.started_at`
    - AND r is a proven ancestor of the binary
    - Matches demo. A genuine crash-after-swap of r's own target does not match, because binary == r.
  - **P2:** P1 plus `c.started_at > r.started_at`. Stricter, but it can miss a reinstall of an existing row, because COALESCE keeps the old started_at (`install.go:3562`).
  - **P3:** the successor is an ancestor of the binary when the binary has moved on again. Weaker attribution.
  - **Not safe alone:** binary is a descendant of r, any or the latest completed row, id order, committed_at or version order, error text.
  - Evaluate against a re-read current row, because the completion UPDATE is keyed by id and not a CAS.

## Acceptance criteria (draft, finalize after the owner's decision)
<!-- AC:BEGIN -->
- [ ] #1 A reproduction (Go/livedb or rehearsal) shows the orphaned in_progress row being completed by flagless recovery after a newer install, RED on rc.16.
- [ ] #2 After the fix, the overtaken row ends superseded with no success callback, and the running version shown everywhere is the installed one.
- [ ] #3 Demo's ledger is corrected through the released software, and the footer shows rc.16 or later.
- [ ] #4 Independent review MERGE; the release gates and both 436 rehearsals pass on the candidate.
<!-- AC:END -->

## Coordination update: 2026-10-06 12:00 UTC, KISS discussion before further coding

- The owner switched coordinator to GPT-6.1 Sol and requested a simple, precise explanation of the actual threat and mechanism. No new implementation, merge, push or deployment is underway during the discussion.
- Lock handoff and this ledger bug are separate. The shipped installer already passes the continuously held descriptor to Go (`install.sh:814-866`), and inline upgrade inherits the descriptor across exec (`cli/internal/upgrade/inherited_lock.go:152-180`). Tokens and contention probes surround adoption but do not provide the continuous hold. Within Go, explicitly passing the held `FlagLock` avoids opening the path again and contending with our own lock. Descriptor lifetime and crash-marker phase correctness are real concerns, not an assumed malicious same-user injection threat.
- A+B+C implementation is unmerged at `eff4aef6d` in `fix/452-overtaken-row`. Round-1 review `tmp/452-review.md` blocked incorrect flagged-route identity certification and concurrent retention deletion. Fixes were locally GREEN, but round-2 review `tmp/452-review-2.md` found two concrete regressions: recovery boot checks out the old flag target before rejecting the resulting executable/HEAD mismatch, and installer completion bypasses the supported resolved clean-build identity. These are not merely hypothetical objections. Normal local suites passed but do not substitute for the failing real-route probes or future released-image guest gates.
- The previous coordinator's 11:55 proposal to discard the branch and implement B alone is not an owner decision. Superseding older `in_progress` rows does not by itself repair demo's already false-`completed` 09.3 row or establish truthful identity in every path. Parked rows remain protected by STATBUS-159/044. Existing A+B+C, D-by-deployment authorization remains recorded while implementation scope is discussed.
- A bounded read-only GPT-6.1 Sol xhigh review is delegated to `session_duck_1791287982917_5ce091e7e894837e`, report `tmp/452-kiss-review.md`. It must assess the simplest trusted fd contract and smallest sufficient ledger repair without assuming either the broad branch or B-only proposal is required. Existing parallel reviewer deer was asked to finish current evidence promptly, without expanding the review. No third implementation round is started.
- Next: present the causal distinction and recommended small contract to the owner, incorporate the independent simplicity assessment, record agreed scope, then use the normal reviewed commit/push/CI/candidate-guest sequence. Demo and Norway remain owner-operated installations.

### Owner direction and corrected work queue, 2026-10-06 12:10-12:18 UTC

The owner authorized scheduling the handoff cleanup first, then the separate ledger move, and left the system running with periodic pokes. Low-level todos must drive delegation, checks, merge and follow-up without waiting for another owner message. Full grounded plan: `tmp/kiss-handoff-and-ledger-plan.md`. Handoff F1-F7 precedes ledger L1-L9, then release/owner-install R1-R5. Each step records its concrete next check and observed completion.

A+B+C/D requirements remain: recovery must not certify an overtaken attempt or notify success for it; successful installer bookkeeping retires other unparked attempts; display uses a shared rule tied to actual deployed full identity rather than completion order; next official install repairs attributable existing false-completed history. Older and newer orphan targets must be considered so a deliberate older install cannot later be undone by the stale attempt's rollback. Parked rows remain untouched. Existing useful route regressions are retained, but the broad singleton/producer/retention implementation is not automatically required and remains unmerged.

Evidence boundary: `tmp/452-review-2-opus.md` is now available, verdict BLOCK. Its new fatal boot/poll observational-health gate and descendant-repair findings are code-traced, not executed. Crab's actual boot and supported clean-build failures were executed. Duck's late provisional simplicity recommendation arrived without source inspection or tests and is not an independent code-review verdict. None is permission to merge. Do not add another broad fix round merely to chase the entire previous branch.

Actual correction to the handoff brief: the existing shell intentionally releases fd9 for a pre-existing recovery marker (`install.sh:542-554`), so not every current path is gapless. The cleanup must preserve recovery intent and released rc.16 receiver compatibility. A filesystem mutex also does not prevent a legacy daemon's SQL claims, as demo proved, so installer cleanup alone is not a permanent barrier.

### Smaller complete repair grounding, 2026-10-06 13:05 UTC

Handoff cleanup remains the active product change. Its new existing-marker route exposed a real interrupted-first-install self-contention; the bounded same-handle correction is frozen at `111bc1e5b`, with actual first-step exclusion/cleanup GREEN, renewed ordinary gates and independent re-review pending. No follow-on push or candidate yet. Initial cleanup is reviewed and integrated locally. Norway remains held.

Next-ledger mapping is delegated source-only to frog, GPT-6.1 Sol, not another broad implementation round. Coordinator read `tmp/452-minimal-provenance-map.md` (63 lines, exact file:line evidence, main source unchanged except ticket notes). Concrete C gap: the current app Dockerfile embeds no immutable full commit SHA. The main image workflow supplies COMMIT but app ignores it, and release workflow's app build supplies none. Runtime configured version/short checkout SHA and either completion ordering do not establish responding-app identity. CLI already resolves its own full executable SHA positively, including the supported clean-build tier.

Small C candidate: stamp a root static build-provenance asset inside each app artifact, include full peeled SHA in both publication paths, fetch the asset from the responding app with no-store behavior, and share one exact-full-SHA `/rest` metadata resolver for footer/admin and executable-aware CLI consumers. No new Next `/api` route. Root Caddy asset requests route to app, not a checkout/proxy image. An open tab must refresh actual responding-app provenance after rollback, not keep its initial injected SHA. Old unstamped images, absent/malformed responses or unavailable metadata remain honestly unknown. Known artifact SHA remains known when its history metadata is pruned. This removes the justification for a new identity singleton, rollback-producer matrix, retention pin or advisory-retention lock for C.

These are source findings and a proposed small delta, not executed acceptance or permission to omit A/B/D. App build/served asset/header/cache, already-open-tab rollback, exact metadata cardinality/equality and history-cap behavior still need real checks. `tmp/452-minimal-ledger-map.md` is the separately delegated bounded A/B/D source map: current flagless completion lock/CAS, installer success bookkeeping, protected parked rows and attributable repair of already false-completed history. Existing main state guards allow the relevant supersede transitions, so no new permission protocol is assumed. Implementation starts only after the exact small scope and reproducing route are grounded, then ordinary independent review and release machinery.

### Delegated minimal implementation checkpoint, 2026-10-06 13:20 UTC

Handoff cleanup has now passed exact frozen111 full Go/static gates and independent MERGE, integrated with five matching patch IDs/all16 source paths equal, and pushed as `cbaff1c5ab17a31f5472993bf2fd810cd60dc4ab` only after every active CI status was empty. CI watcher `414710lqkk` checks explicit conclusions and Fast Tests exercised-SHA attribution. At 13:18 UTC five product workflows green, one pending, zero failures. No candidate cut or production install.

Complete bounded A/B/C/D contract: `tmp/452-minimal-repair-plan.md`. One new isolated shared tree `scratch/fix-452-minimal`, branch `fix/452-minimal`, basecbaff. Broad eff4aef6d remains unmerged evidence only. Two fresh GPT-6.1 Sol implementation agents, low effort, own disjoint files: wolf `session_wolf_1791292560701_4c6bf36c3b384f56` owns A/B install.go/service.go and narrow real-route helpers/tests, horse `session_horse_1791292590219_4b71eb2c870726d1` owns C app/build workflows/new exact metadata RPC/types/tests and executable-aware upgrade CLI. Frog `session_frog_1791289010522_6666a31e6e9659df`, high effort, owns tmp-only D attribution prototype, no tracked writes. Explicit-file commits/index coordination, one broad Go suite after shared freeze, then fresh exact-HEAD independent review. No new singleton, retention pins/advisory locks, resident/HEAD equality or fatal boot health gate, box-specific IDs/tags, new ownership protocol or omitted D.

A actual baseline observed by coordinator: `tmp/452-ab-route-red.log` and `.exit`=1, real `Service.completeInProgressUpgrade` on owned PG18 clone. Overtaken old row becomes completed, local fixture callback fires, later install_last_error is erased. Genuine exact-target and descendant crash WITHOUT intervening completion both pass. Real PostgreSQL/Git, external Docker/serving boundaries controlled by existing test seams. This is not a released-image guest proof. No permanent A/B source edits preceded RED. Next is rollback-only witness/CAS prototype before bounded production edits.

C actual baseline observed: `tmp/452-c-baseline.log`, two behavioral failures: unstamped artifact still falls back to configured name/short SHA, legacy unkeyed parser accepts another full SHA without provenance binding. A small artifact/runtime-separation and exact-equality prototype executed GREEN in `tmp/452-c-prototype.cjs/.log`. It is synthetic groundwork, not HTTP-cache/app deployment acceptance. Production C will use `public.release_identity(p_commit_sha text)` returning existing four metadata columns by exact SHA, keep old no-arg RPC for released clients, and preserve unknown metadata honestly. Invoked new target executable is NOT previous serving app identity, so installer source metadata must not swap one history guess for that different guess.

D concrete counterexample found from released source: direct `./sb install` can genuinely finish an already-in-progress older row while preserving started_at. Chronology and no re-claim alone would misclassify it. Its retained completion event uses INSERT ON CONFLICT, unlike daemon UPDATE completed_at=now. Frog is executing positive demo and genuine direct/scheduled older-install controls using existing event semantics and Git ancestry. Shared daemon query is not claimed to uniquely identify flagless versus normal pipeline. No hard-coded demo IDs and no newly required historical marker. D implementation waits for the small executable attribution result, not another broad architecture round.

DB safety: verified Docker PostgreSQL18.6 at local port3014, own clones ONLY `statbus_452kiss_ab_route_pg18_1006`, `statbus_452kiss_c_metadata_1006`, `statbus_452kiss_d_attribution_1006`. Shared seed/main/template/prior reviewer DBs read/clone only, never dropped, replayed or blessed. Every mutating session asserts exact owned current_database, all actual selectors/livedb overrides explicitly owned, no dev.sh bootstrap. Native port5433 was actually PostgreSQL17 despite a PG18 client, and a partial owned restore failed on missing extensions/roles. It was retained as diagnostic, not misrepresented as a PG18 test. Secret-bearing dump mode600, never staged/printed, removed only with fixture lifecycle later. Docker mounts point at main, so new fix SQL/test files must be supplied explicitly.

Next wake-up: read CI watcher and worker actual RED/prototype/GREEN logs, authorize D only on observed predicate, freeze complete ABC/D source, one coordinated full gate pass, independent exact review, reviewed merge and fresh CI-idle push. Existing candidate image/guest machinery follows, then owner demo observes truthful identity/history/callback and stability, then Norway human canary, then stable. Norway is still held.

### D attribution decision and actual target evidence, 2026-10-06 13:27 UTC

Coordinator read `tmp/452-d-attribution-report.md` (50 lines), actual owned-PG18 prototype SQL/output and explicit exit0. The refined predicate selects the reconstructed demo sequence while excluding two reachable genuine older installations: direct installer INSERT/upsert preserves started_at but is not the daemon completion operation; rescheduled daemon installation resets the attempt start and claim before completion. Guarded retraction and idempotent second-run tests pass, preserving a later install failure key. This is an overtaken-daemon-attempt correction, not a claim that query text uniquely identifies flagless recovery or proves historical physical serving containers. The current single-active constraint excludes a fresh concurrent daemon claim while the same old attempt remains continuously in_progress. A resumed original daemon after an overtaking install still belongs to that superseded attempt.

The remaining actual-demo evidence gap was closed at 13:25:38 UTC using the existing SSH access with ONLY SELECT statements inside BEGIN READ ONLY/ROLLBACK. `tmp/452-demo-d-evidence.sql`, `.log`, `.exit`=0 show row25829 still has the original start/completion/NULL claim, independently completed row227493 remains the strict descendant witness, and the final two retained events are claim801727 then daemon completion801728. The complete original query exactly matches the released normalized daemon UPDATE. No install, mutation SQL, service control or callback ran. IDs/tags occur only in evidence and fixture chronology, not product selection.

At 13:26:36 UTC wolf was authorized to implement the bounded generic D helper through normal successful installation under the already held mutex. Predicate: unchanged completed/unparked r; distinct completed c strictly between r.start and r.false-finish; proven strict rSHA->cSHA and c equals/ancestor of successful installed full SHA; adjacent retained claim and daemon-completion events with no intervening state/park/reset. Unknown/missing evidence is not selected. Re-read/lock r and c, CAS unchanged attempt/snapshot disposition, set superseded/superseded_at and completed_at=NULL. Log original timestamp/witness/event evidence through the existing installer log before disposition. Preserve error, backup/log pointers, history and later failure keys; never notify success for the old row. Actual normal runInstall, genuine direct/scheduled older controls, changed/parked/missing evidence and idempotency are required before completion credit. No registry, new historical field, box-specific repair or broad sweep.

A/B worker has reported saved prototype/real-route GREEN and baseline overlay RED; coordinator is reading exact artifacts before marking them complete. C actual app-server probe exposed a login redirect on the new static asset; the fix is only an exact public-path exemption. A separate existing production build defect exports exportOrder from a Next API route; base source confirms it predates C. Authorized a separate behavior-preserving helper extraction, not a dependency upgrade or routing rewrite. Both new actual integration findings must be checked, not excused.

CI observation correction: watcher414710lqkk was killed by its tool's 600-second timeout at13:23:40, exit124, with no product failure. Five expected workflows were successful and exact Fast Tests37469525031 was still in_progress. Replacement watcher0422886ax6 retained explicit exercised-SHA/conclusion checks and completed at13:29:11 UTC with all six expected workflows successful and exit0. No new product push or candidate.

### Complete minimal source frozen, 2026-10-06 13:44 UTC

Shared implementation is clean and frozen at `2a590a7772371e9ca0136138b3a06fa433d8fa80`. Coordinator read both complete worker reports, `scratch/fix-452-minimal/tmp/452-ab-final-report.md` and `tmp/452-c-completion.md`, actual RED/GREEN logs and explicit exits, product deltas and fixture boundaries. Commits: A `e6fd5b0c6`, B `eb53540e5`, C RPC `74900907a`, separate existing export-order build correction `fcf2ea6c0`, C app `ee8580376`, C positive program resolution `c1f46218a`, D `6070abc32`, missing-actual-log guard `2a590a777`. Nothing from the rejected broad singleton/retention branch was merged. These commits remain on the isolated implementation branch, not master.

A eight actual recovery modes and existing Behind rollback are GREEN: overtaken, exact crash, descendant crash without independent completion, inherited hold, competing hold, changed late claim, unknown program evidence and resource park. PostgreSQL and Git are real, external Docker/serving steps are controlled fixtures. Existing convergence helper and wiring checks pass, but they do not execute the newly moved early-handle promotion entry. Its acceptance remains the existing real candidate convergence arc, explicitly not claimed as local coverage.

B actual normal runInstall baseline RED and seven corrected modes GREEN were inspected. Normal successful new-row/terminal-refresh/intentional older installs retire other unparked active rows independent of own upsert outcome. Failed/dev/bypass and parked rows remain untouched, backup/error evidence preserved. Previous source is unknown rather than misusing latest completion or invoked target.

C artifact stamp is five lines, consuming image-only full SHA, copied with the app public files. Both publication workflows prove the checked-out full SHA. Actual production Next response has HTTP200 and Cache-Control:no-store, with runtime configured target unable to fabricate identity. The actual client atom refreshed target marker to restored-source marker to unknown against real local production HTTP, not mocked responses. Marker swaps simulate rollback, not a Docker rollback. Local Next has no PostgREST route; runtime metadata was unknown there. Exact metadata, old SHA outside100, promotion, anon privilege and pruning were independently exercised on real owned PG18 by pg_regress332. Separate behavior-preserving exportOrder extraction fixes an observed preexisting production build failure; actual `next build --webpack` passed without bypassing typechecks.

D actual normal runInstall baseline RED and final nine modes GREEN were inspected: exact demo chronology with NULL claim repairs, genuine direct/rescheduled older installs remain completed, missing/changed/park evidence does not authorize, changed attempt/snapshot/completion CAS denies, installing an older target does not repair, current parked row stays parked. Original completion timestamp, witness and event references are written to the existing installer log before retraction; missing actual log denies correction. False completed_at is removed, snapshot/log pointers preserved, repeat success produces no new old-row state events. This is positive attribution of an overtaken daemon attempt, not invented historical physical app identity.

Fresh independent GPT-6.1 Sol xhigh reviewers: koala `session_koala_1791293896038_eb13be2848b73694` for C/export correction, llama `session_llama_1791293977058_0ce9874926638417` for A/B/D, both final frozen2a source. Own detached reviewer trees, focused relevant tests only, no shared source/index or production operations. Only newly owned `statbus_452kiss_ab_review_1006` is authorized for ledger review after exact PostgreSQL18.6/current_database verification; protected DBs remain read/clone only. Verdicts pending, no merge permission inferred.

The sole coordinated CLI pass `285495x2lh` stopped at 13:45:23 UTC, exit1. Exact frozen2a gofmt, build and vet passed, then lint reported exactly three issues: two unchecked deferred transaction Rollback results in install.go/recovery_attempt.go and a DeMorgan simplification in recovery_attempt.go. The broad Go suite did NOT run. Failed `tmp/452-gate-lint-2a.log/.exit` remains evidence. Wolf is assigned only these lint corrections as a separate commit, then the coordinator will freeze a new clean pin and rerun one full pass. Horse owns one sequential exact2a app tsc/lint/Jest pass. No overlapping broad Go suites. The command-wrapper's first diagnostic-filename gate refused without running; corrected absolute log paths and pipefail started the sole actual pass. Native todos retain every pending review/integration/CI/release/install wake-up. Completed handoff/grounding IDs are preserved in `tmp/452-completed-todo-archive-20261006.md`, not silently forgotten. Normal candidate image/guest gates, owner demo and Norway remain mandatory.

### Concrete review blocker and bounded correction, 2026-10-06 13:51 UTC

The three lint findings were corrected by separate commit `d68625dca76693a6103ed9a70eae99de42984aa3`, exactly three changed lines across install.go/recovery_attempt.go. Coordinator read the clean immutable source and actual focused lint0issues. Full exact2a app tsc/lint/Jest passed, explicit start/end HEAD equal and clean status: ten suites,56tests, zero lint errors and five existing warnings. C/export source is byte-identical at d686. Koala's independently executed C/export-only MERGE report was read in full, preserving candidate publication/real container rollback boundaries.

Llama found and executed a concrete BLOCK: after a normal successful D correction writes its only original timestamp/witness/event attribution into the install log, a legitimate immediate repeated install in the same second truncates that file. `NewInstallLog` uses a second-resolution name and `os.Create`; `NewUpgradeLog` already avoids this exact collision with exclusive creation and numbered suffixes. The reviewer test adds only timing alignment and the retained-log assertion to the actual normal runInstall path. A/B/D and Behind sibling routes pass; this log-loss failure is not an imagined lock-injection threat.

Coordinator cancelled the sole d686 full gate `575122hrbg` at13:50:24 before authorizing shared source edits. Its partial logs remain, not a full-suite PASS. Wolf is assigned only install-log exclusive collision handling, a deterministic same-start log test and the actual retry/audit-retention regression. Require frozen d686 RED, bounded product change, focused GREEN, clean new immutable pin and independent formerly failing-route re-review. No ledger policy, provenance, registry, retention, health gate or new ownership protocol is authorized. Then rerun one coordinated full CLI gate before MERGE/integration/push.

At13:53 UTC the bounded repair froze clean at `47b278ea2e9a6bc5bdeeb685ca9e21c9e5afdc13`: only progress.go, new install_log_collision_test.go and the actual normal-installer history test, +65/-7 including tests. Install logs now use the already-established O_EXCL plus numbered-suffix policy instead of truncating an existing file. Deterministic first/second/third same-start invocations preserve the first log byte-for-byte; the unchanged upgrade-log collision control passes. The actual normal runInstall retry now asserts original saved attribution bytes still exist after the successful idempotent retry. No policy, metadata or recovery gate changed.

Coordinator read exactd686 actual retry RED `tmp/452-install-log-route-red.log/.exit`=1, deterministic collision GREEN `.exit`=0, all nine actual normal-install history modes GREEN `tmp/452-install-log-route-green.log/.exit`=0 and focused lint0issues. Existing owned `statbus_452kiss_ab_route_pg18_1006` only, no new DB/shared mutation or worker broad suite. Fresh immutable47b was sent to llama for the independent original failing-probe re-review and koala for unchanged C/export scoped equality. Sole final full CLI pass `840751tjos` started13:54 UTC with clean47b asserted and `tmp/452-gate-{gofmt,build,vet,lint,unit,diff}-47b.log/.exit`; it finished13:58:15 UTC after239.7s, exit1. Gofmt/build/vet/lint passed. The initial report named only TestDaemonSchemaFloorBumpGuard and TestEveryPostSnapshotWriteSiteIsAccountedFor_STATBUS242, but a direct retained-log reread at14:22 UTC confirmed FOUR failures, also including TestFlagInvariant_EveryPhaseAndBackupPathWriterIsAccountedFor_STATBUS232 and TestTypedComposeAuthorityGate. The earlier two-failure summary was incomplete. None of the failures is dismissed or hidden. Horse owns the existing-policy floor20261006132000 acknowledgement and exact source-derived livedb claim-floor history expectation; wolf owns five explicit rollback-audit dispositions with actual lifetime rationale, including the nonexecuted daemon-query fingerprint literal. No guard/parser weakening, metadata architecture or production ledger redesign. Both scoped corrections need focused RED/GREEN, independent exact-pin review and a new full gate before integration.

### Frozen integration-contract corrections, 2026-10-06 14:19 UTC

The three bounded corrections are committed and clean at `4a659b1af28f7d11480cdbd5dd473631113a3e2e`: `4c0e01a66` adds the five explicit rewind-audit dispositions, `b191b074b` updates the daemon-floor constant/rationale, and `4a659b1af` retains exact applied-history equality using the actual on-disk migration range. Coordinator inspected every delta. Audit's real existing check is RED before and GREEN after, with focused lint0. Floor guards, consumers and focused lint pass. No scanner/parser exemption, guard-count weakening, new recovery gate or ledger architecture was added.

The livedb claim-floor file compiles with `go test -c -tags=livedb`; its full replay was not executed locally. Its existing hardcoded template prefix is outside the agents' approved DB scope, so no naming seam, creation/drop or protected replay was performed. The worker's initial no-tests `go test` reached TestMain configuration validation and failed before DB setup; that failure is retained, not represented as a database pass.

Independent llama's full47b ledger MERGE and retained original BLOCK were read. The unchanged formerly failing actual normal retry probe passed5/5 and collision controls10 repetitions each; A/B/D and real PG locking/CAS controls passed. Llama now audits only the final five classifications, and koala audits floor/history plus C/export byte equality at exact4a659. Sole root CLI gate `327193y5fq` started14:18:47 with clean exact4a659 asserted, new explicit exit logs, and no overlapping broad worker suites. Gofmt/build/vet/lint passed; full Go remains in progress. No merge/push/candidate or production repair has been claimed. Final independent MERGE, complete local gates, normal candidate-image guest gates and owner deployment are still required.

### Remaining inventory corrections and honest failure count, 2026-10-06 14:24 UTC

The full4a659 gate327193 finished at14:22:15 after208.61seconds, exit1. Static checks and the floor/rewind audit corrections pass. The complete log's actual FAIL headers show only two remaining checks: phase/snapshot writer inventory and typed command authority inventory. These had also failed in the previous47b run; the coordinator missed those two headers in the earlier summary. The prior record above is corrected, and both original full logs remain unchanged.

Wolf is authorized to change only backup_path_carriers_test.go and compose_authority_types_test.go: account for held.Phase/held.BackupPath as one faithful post-swap parking update, and account for the two exact read-only Git merge-base ancestry sites with count1 and their actual purposes. No production changes, scanner/count weakening, blanket command permissions, DB operation or broad worker suite. Require existing RED, focused GREEN/lint, a separate commit and clean final pin. Llama reviews the final two-file delta; koala proves unchanged C/floor/history source. Both4a independent MERGE reports were read, but the next full gate and final reviewed integration remain pending. No push, release or deployment is claimed.

At14:26 UTC the bounded inventory correction froze clean at `551de7250606381d9c5a96cfb196fb540b47b185`: exactly four inserted lines in those two existing tests, no product change. Coordinator read both original RED failures, final GREEN including reason/count and new-compose rejection controls, lint0, exact diff and clean formatting. The paired marker copy remains one post-swap persistence through the already held handle; the two Git commands only establish ancestry and do not receive compose-launch permission. Original scanners and enforcement are unchanged.

Sole final CLI pass `8165697igg` started14:26:56 with exact clean551 asserted and new explicit exit logs. Through14:29 UTC static checks pass and full Go is still running, not claimed passed. Koala's final exact551 C/export/floor/history MERGE and byte equality were read. Llama is independently pinned to551 for the two new inventory entries, with final verdict pending coordinator inspection. App source remains identical to the tested56-test checkpoint, and real PG route/SQL evidence remains attributable to its unchanged source. Real candidate-image/guest acceptance and owner deployment remain pending.

### Final local validation and independent MERGE, 2026-10-06 14:34 UTC

Exact551de finished14:30:06 after190.34s: gofmt/build/vet/lint0issues and complete `go test ./... -count=1` each exit0, every package passes. Wrapper8165697igg exit2 occurred afterward on eight generated psql aligned expected332 header spaces; original wrapper/diff failure retained. Existing327/331 use the same formatting. Strict source diff passes outside that exact generated file;332 passes allowing only aligned end-of-line blanks and is byte-identical to real PG18 regression output. No fixture or whitespace policy changed and no successful suite reran. Start/end source is unchanged and clean at551de.

Both final independent MERGE reports at exact551de were read: koala C/export/floor/history, llama A/B/D/log/final inventories. Reports remain tmp/452-minimal-c-review.md and tmp/452-minimal-ledger-review.md. They retain real candidate-image/guest acceptance boundaries. Next: integrate14 explicit reviewed commits, prove patch IDs/source equality, freshly verify all CI idle before one push and observe exact-SHA CI including attributed Fast Tests. Ticket remains In Progress until candidate gates and official owner deployment, no production repair claimed.

### Reviewed integration, 2026-10-06 14:38 UTC

All14 approved commits were cherry-picked conflict-free after ticket-only checkpoint5208656f6. Integrated product HEAD1766403fda37491291799eb3e44f12d8c98c99e5. Each original/integrated stable patch ID matches; all47 changed paths and the complete repository outside backlog notes are byte-identical to tested/reviewed551de. Strict source/scoped generated-output diff checks pass. Tracked tree was clean; unrelated untracked .yarn preserved. Proof/mapping: tmp/452-reviewed-integration-20261006.log and tmp/452-patch-source-proof-20261006.log.

Integrated commits in order: b4acfeb70, cda000a81, d7fb34fc5, 885aabafd, ede6945d8, b994c30a1, 13959bd6a, c0878c1d1, 568bb248f, 6c0e46b68, 08cb26582, 576f7d9a1, 5d995fa6a, 1766403fd. No rejected broad branch or unreleased side change was imported. Next: fresh all-CI-idle check, one push and exact-SHA conclusions including Fast Tests, then remaining blocker gate and ordinary named-candidate guest machinery. Integration is not a demo repair or release acceptance claim.

At14:40:24 UTC the final inline query found queued/in_progress/requested/waiting/pending all empty, including every event type. One push completed14:40:41 and origin/master was positively verified as49bb3f1a5817cd25d8986c9da2b581fd83258653. Source still equals reviewed551de; final SHA adds only the merge-record ticket commit. Exact-SHA watcher646741rtpl started with sufficient deadline/notification/wake. At14:41:26 the five initial product workflows were queued/in_progress; Fast Tests must later be attributed by exact exercised-SHA title. No CI success, candidate cut or deployment is inferred. Push evidence tmp/452-master-push-20261006.log; observer tmp/452-ci-49bb3f1a5.log/latest.json/exit. No second push until every CI run is terminal.

At14:48 UTC the watcher was confirmed terminal exit1 after app run37480974869 was cancelled. Its annotation identifies a competing app-build-lint-master request; run37481254979 is a Dependabot sharp branch push, not another master push. Both app/Go non-PR groups incorrectly share master across branches, now bounded STATBUS-453. Original cancellation evidence remains tmp/452-ci-app-cancellation-20261006.log. Go, Harness, Images and Notify passed; exact Fast Tests37481764536 remains active. The app run is not counted as successful, and neither a release nor demo repair is claimed. Corrected-source CI and normal candidate-image guest acceptance are still required.
