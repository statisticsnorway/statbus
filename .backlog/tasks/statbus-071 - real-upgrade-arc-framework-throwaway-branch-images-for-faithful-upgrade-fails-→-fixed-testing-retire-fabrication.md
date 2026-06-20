---
id: STATBUS-071
title: >-
  real-upgrade-arc-framework: throwaway-branch images for faithful "upgrade
  fails → fixed" testing (retire fabrication)
status: In Progress
assignee:
  - engineer
created_date: '2026-06-17 09:05'
updated_date: '2026-06-19 23:22'
labels:
  - install-recovery
  - upgrade
  - testing-foundation
  - architect-plan
  - doctrine
dependencies: []
documentation:
  - doc-012
priority: high
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why this exists (the goal)
The barrage of tests that proves, on real machines, that a StatBus box can be **installed → upgraded → hit an issue (or not) → fixed → upgraded again**, and come through with its data intact, entirely on its own. This is what earns the confidence to cut a release. (A release is cut only after its candidate passes — including a run against the **large Norway database**, to catch slow or runaway migrations a small database would never reveal.)

Every upgrade below runs through the **real operator path** — no faked crash states.

## How the test drives a real upgrade
Four CI jobs: **construct → image-wait → run-arc → teardown**.

1. **construct** — off the starting commit **A**, make two throwaway branches and have their images built:
   - **B** = `test/<scenario>-migration-<run-id>` — A + the migration under test.
   - **C** = `test/<scenario>-fixed-migration-<run-id>` — B with that migration corrected in place.
   Pushing them triggers `images.yaml`, which builds per-commit images `statbus-{app,worker,db,proxy,sb}:<commit-short>`.
2. **image-wait** — wait until all five images exist for A, B, *and* C.
3. **run-arc** — on a fresh Hetzner VM:
   - **Install A** (pinned to the exact commit) + load demo data.
   - **Upgrade to B, the operator way:** `./sb upgrade register <B>` → `./sb upgrade schedule <B>`. That writes a row into **`public.upgrade`**; a database trigger wakes the **upgrade service**, which claims the row and runs the upgrade on its own. The test watches `public.upgrade.state` until `completed`, `failed`, or `rolled_back`.
   - **Upgrade to C** the same way.
   This is the **Albania path** — the same path the web "upgrade" button uses: no SSH, no deploy-branch, the box acts autonomously.
4. **teardown** — delete the two throwaway branches.

## What each branch contains
| Branch | Contents |
|---|---|
| **A** (base commit) | What gets installed first. |
| **B** = `test/<sc>-migration-<run>` | A **+ one new migration V**. |
| **C** = `test/<sc>-fixed-migration-<run>` | B **with V edited in place** — same file, corrected; not a new migration on top. |

**How V's number is chosen:** *not* the wall-clock time the branch is made — the harness takes the **highest existing migration number and adds 1**. That's the smallest number that still sorts *after* every migration in A, so V is genuinely *pending* when the box upgrades A→B. The working V is real and observable: it creates `public.upgrade_arc_fixture(id, note)` and inserts `(1,'arc')`, so the test can confirm V actually ran.

## What the box does when a released migration is *fixed* (the rule the arc relies on)
A released migration is immutable. The **only** legitimate reason to change one is to **fix a genuinely broken migration** — one that crashed, timed out, or ran out of memory on some hosts. A discretionary change to a *working* migration is **not** allowed. Fixing a broken migration is a deliberate, declared act at the release cut, which the release-candidate gate enforces — so any changed migration that reaches a release is an intentional broken-fix.

Once such a fix ships, a box handles it three ways, by where it runs:

1. **A developer's machine → error.** Stop; let the developer choose — migrate down then up, or recreate the database. A human is present; don't guess for them.
2. **The dev.statbus.org edge box → re-run it (roll down, then up).** It detects the dev channel and re-runs the migration so it always runs the **latest** code. This is deliberate: dev's whole purpose is to run the newest commit every day, so we catch breakage commit-to-commit. Losing data there is fine — it's only dev.
3. **Every real install (pre-release or release) → adjudicate, never roll down:**
   - the fix is **not yet applied** → **apply it**.
   - the broken migration was **already applied** → **accept the fix**: re-stamp the record *without* re-running. Safe because a broken-fix changes only *whether* the migration finishes, never *what* it produces. Trust earned by passing the release gate.

The thread: **human present → error; unattended dev → redo (data loss fine); real install → trust the gate and accept the fix (never destroy data).**

## The two stories the arc proves
**1 — A broken migration that already ran (the many).**
A released migration was broken — it timed out or failed for *some* hosts — but it **succeeded** for the many (e.g. small databases where it ran fine). The fix ships. On a real install the box **accepts the fix** (case 3 above): re-stamps the record without re-running — safe because the fix changes only whether the migration finishes, not its result. Proves a box that already ran a migration takes its fix without breaking. **[the re-stamp mechanism is built · green on a real VM; reframing the test fixture from amend-a-working-migration to a genuine broken-fix rides STATBUS-102]**

**2 — Upgrade fails, rolls back to a clean slate, fix applies fresh (the few).**
A real migration fails in one of **three ways**; the box rolls itself back; the fix (C) then applies cleanly.

| # | How the migration fails | Kill source | How the test triggers it |
|---|---|---|---|
| 1 | **Fails to apply** (a plain error) | none — errors by itself | `DO $$ BEGIN RAISE EXCEPTION … END $$;` |
| 2 | **Stalls → timeout → aborted** | **internal** — our own timeout | a max migration runtime (target **12 h**, set to **seconds** in the test) fires and kills V mid-run; V announces start then sleeps (`NOTIFY …; SELECT pg_sleep(N);`) |
| 3 | **Eats all memory → OOM-killed** | **external** — the OS kills Postgres | reproduce the *effect* without exhausting memory: V announces start and sleeps; a listener confirms it's mid-run, then **kills PostgreSQL from outside**, as if OOM fired |

**All three converge on one recovery — the centerpiece check:** after rollback the database is **logically identical to A** — same schema, same migration ledger, same data — so **C applies the corrected V fresh and the upgrade completes**, data intact. (The test checks this by comparing a *normalized* dump of schema + ledger + data against A's — not raw bytes, which can legitimately differ after a rollback, e.g. a sequence that advanced.) That logical-identity guarantee is the one property no faked test can prove. **[failure 1 built · green; failures 2 & 3 designed]**

## The same flow, crashed at *other* points (the kill family)
Beyond the migration itself, the test also injects a *real* crash or stall at other points of the upgrade — fetching the new code, the pre-upgrade backup, the binary swap, *between* two migrations, *just after* a migration commits but before it's recorded, during the rollback itself, and while the box restarts — and checks the box still recovers on its own. **[most already on the real `register`+`schedule` path and proven; the "just after commit, before recorded" kill is the one still to build]**

## What's there vs. not
- ✅ The many (a broken migration that succeeded for them → accept the fix, no re-run) — re-stamp mechanism green on a real VM.
- ✅ Failure 1 (error → rollback → logically back to A → fix applies fresh) — green. *The framework's unique value.*
- ⬜ Failure 2 (internal timeout-kill) — designed; needs the configurable 12 h ceiling.
- ⬜ Failure 3 (external OOM-kill of Postgres) — designed; needs the `NOTIFY`-handshake kill.
- ⏳ Kill-at-other-points family — most proven; the after-commit-before-recorded kill remains.
- 🧹 Clean-code-ship (STATBUS-102): rip out `amendments.tsv` + the `circumvent`/`amend` vocabulary; the box accepts a broken-fix by channel-trust, not a per-version file; reframe the working→fixed arc to a genuine broken-fix.

*Full pre-cleanup design notes and the run-by-run history are preserved in the Implementation Notes below and in this task's git history.*
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 WORKING arc GREEN on a real VM: install A → B applies migration V → C re-stamps V's content_hash autonomously; data intact; zero orphan branches/VMs
- [x] #2 FAILING arc GREEN on a real VM: install A → B's V deliberately fails → box rolls back to 'rolled_back' → clean-slate fingerprint equals the post-A baseline → C applies the fix fresh; data intact
- [ ] #3 Kill-family scenarios reshaped: the FABRICATED scheduled-upgrade row replaced by a real register+schedule (086); the crash stays real (existing inject / external NOTIFY-handshake kill)
- [ ] #4 fabricate_scheduled_upgrade_row DELETED with zero callers; NO synthetic crash-state fabrication remains anywhere (King's no-residual rule)
- [ ] #5 STRETCH (product-pristine): in-migration-SQL inject hooks retired in favour of the NOTIFY-handshake + external-kill-timing where feasible; remaining hooks limited to the Go-internal windows that no SQL can reach, each justified
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
STANDALONE FIDELITY (King correction, 2026-06-17) — CORRECTS the cloud-centric framing. Albania is the FIRST REAL EXTERNAL STANDALONE: a customer box physically inside Albania, NO SSB remote access (no SSH, no deploy branch). Deploy branches (ops/*/deploy/*) are CLOUD-only (niue). Albania's ONLY upgrade path: the box discovers a new GitHub RELEASE -> a LOCAL operator schedules it via the WEB INTERFACE (writes the public.upgrade row) -> the upgrade service applies + recovers AUTONOMOUSLY; SSB CANNOT intervene if it breaks. IMPLICATION for this framework: the branches/images only SUPPLY the A/B/C test artifacts (cheap, no permanent tags); the test must DRIVE the upgrade through the SAME scheduling mechanism the web UI uses (the public.upgrade row), and assert the box applies+recovers ON ITS OWN (model the no-remote-rescue reality). branch-vs-tag is just the test's cheap proxy -- production standalone upgrades come from release TAGS, but both procure BY COMMIT so the apply+recover path the test exercises is identical. This CORRECTS STATBUS-034's 'channels = ops/*/deploy/* deploy branches' framing (cloud-only). SEPARATE CONCERN: GitHub-release DISCOVERY (the box finding new releases) is standalone-specific and tested apart from apply+recover. CONSEQUENCE: the amend-an-applied-migration arc (STATBUS-072) is THE first scenario -- a remotely-unrescuable box must auto-apply an amended-migration release without crashing and self-recover if it does = the literal Albania failure mode. Albania is live + blocked NOW (cannot upgrade because the current path crashes), so this is present urgency, not future direction.

FINALIZED BRANCH SCHEME (King-converged, 2026-06-17). NAMING = FLAT siblings under test/ (the King's 3rd option) — the only git-valid scheme: VERIFIED that `git branch test/base` then `git branch test/base/hanging-migration` FAILS with `cannot lock ref ... 'refs/heads/test/base' exists` (a ref name can't be both a file and a directory), so the nested variants (test/base/hanging-migration/...) are impossible. Branches:
  test/base
  test/hanging-migration        test/hanging-fixed-migration
  test/working-migration        test/working-fixed-migration
LINEAGE: the 'build on each other' lives in the GIT COMMIT ANCESTRY, not the branch-name path. base = base commit; *-migration = a commit on top of base adding migration V; *-fixed-migration = a commit on top of *-migration that EDITS V's file IN PLACE (same version, corrected/amended bytes — NOT an additive fix-on-top, which would re-run V_broken). Tree at *-fixed-migration therefore carries the corrected V.
TWO ARCS = the two amend-migration populations (STATBUS-072):
  - working-migration -> working-fixed-migration: V SUCCEEDED then amended -> box RE-STAMPS (the MANY). [first scenario to build — the literal Albania case]
  - hanging-migration -> hanging-fixed-migration: V hangs/fails then fixed -> box RECOVERS + re-runs (the FEW).
CI TRIGGER: add `test/**` to images.yaml's push trigger (one line); the branch-name SUFFIX selects which scenario/arc runs. 'Trigger automation from the branch name' = satisfied.
STANDALONE FIDELITY (Albania): the test DRIVES the upgrade via the SAME scheduling mechanism the web UI uses (write the public.upgrade row) and asserts the box applies+recovers AUTONOMOUSLY (no remote rescue) — NOT a deploy-branch pointer move (that's cloud). branch-vs-tag is the test's cheap proxy; production standalone upgrades come from release TAGS; both procure BY COMMIT, so the apply+recover path the test exercises is identical. (Box-discovers-a-new-release is a separate standalone concern, tested apart.)
CENTERPIECE ASSERTION: after the failing upgrade rolls back, DB == base byte-identical, then the fixed upgrade applies clean (clean-slate-after-rollback).
This supersedes the cloud-channel framing; STATBUS-034's 'channels = ops/*/deploy/* deploy branches' was cloud-only.

ARCHITECT DISPATCHED to plan (2026-06-17 ~20:20), at King's prompt — turn the captured design (resolved branch scheme + B/C topology + clean-slate-after-rollback + Albania standalone-fidelity) into an IMPLEMENTATION-READY spec the engineer can build from: (a) images.yaml `test/**` trigger; (b) throwaway-branch workflow (branch→commit B+C→image-wait STATBUS-056→run arc→teardown STATBUS-057); (c) FIRST scenario = amend-migration/Albania case (working-migration→working-fixed-migration, STATBUS-072) driven via the public.upgrade web-UI row, autonomous apply+recover; (d) clean-slate-after-rollback mechanics; (e) 056/057/067/072 deps. PARALLEL to the rc.04 re-run (design only, NON-gating). A-vs-B decision RESOLVED = B (follow-up): close rc.04 first, build this immediately after — King + foreman aligned (King: 'once rc.04 passes, we can look at the framework'). Re-run triage takes priority over this planning if a scenario goes red. Architect reports the plan to foreman for King review.

IMPLEMENTABLE BUILD-SPEC ready (architect, 2026-06-18): backlog doc-012 "STATBUS-071 build-spec: real-upgrade-arc framework". Covers (a) images.yaml test/** trigger; (b) branch fixtures test/base + test/working-migration→working-fixed + test/hanging-migration→hanging-fixed with exact commit contents; (c) the working (succeed→amend→re-stamp/Albania) + hanging (fail→rollback→fix, crash + too-long/OOM-at-both-data-sizes) migration fixtures; (d) upgrade-arc-harness.yaml 4 jobs (construct→image-wait→run-arc-via-register+schedule→always-teardown); (e) clean-slate fingerprint (schema+ledger+data sha256); (f) inject-on-real-upgrade points (migrate.go :388/:436-438/:911/:420) for the kill arcs; build order + deps (056/057/072/067). Test driver = STATBUS-086 register+schedule (NOT fabrication). §7 documents BOTH *-fixed topologies (edit-V-in-place per 072 vs add-forward-V+k) as the KING'S open decision — does NOT block the spec; foreman puts it to the King at STEP-2 start.

arc (c) GREEN — run 27784916284 SUCCESS (2026-06-18, foreman autonomous drive). FIRST real-upgrade-arc proven on a VM: install A → A→B applied real migration V autonomously (register→schedule→daemon executeUpgrade, ephemeral-signed commit trusted) → B→C re-stamped content_hash (H_B=ab549269→H_C=4f65f4eb, V's effect preserved, exactly ONE ledger row) → PASS, data intact, healthy, ZERO orphans, all 4 jobs green. Proves the 072 amend-conveyance (re-stamp / MANY-who-succeeded population) end-to-end via the autonomous Albania path.

Took 4 runs to harden the harness (each found by a run, fixed through the foundation): (1) dispatch ref-race; (2) HCLOUD_NAME_PREFIX guard → statbus-arc- (ddb6bc25d); (3) commit-signing — ephemeral ed25519 key signs B/C, arc's install trusts the pubkey (4336affb1); (4) checkSignersDone scrub — install pre-flight-1 :352 verifies allowed-signers vs HEAD=A with {arc}-only (jhf added at :358), arc can't sign A → :1638 scrub-all → FIX: inject arc POST-install (config-gen doesn't run checkSignersDone) + restart statbus-upgrade@ unit (a2d485285; diag+dotenv regression test bd437370b). dotenv layer exonerated by cli/internal/dotenv/spaced_signer_test.go. NEXT: increment (d) failing→fixed arc + base-tables-only 3-dim clean-slate fingerprint.

=== STATE + DOCTRINE + OWNERSHIP (foreman, 2026-06-18, King asleep, autonomous drive) ===

OWNERSHIP (applies to all arc work here):
- BUILD / assignee = engineer (commits nothing).
- REVIEW = architect (design + correctness) THEN foreman (diff review).
- COMMIT + VM re-fire = foreman (per CLAUDE.md: agents don't commit; foreman commits + fires the paid VM runs).
- Diagnosis / instrument / log legwork = mechanic + operator as foreman dispatches.

STATUS:
- WORKING arc (c) reached GREEN earlier (run 27784916284): install A → B applies V → C re-stamps; data intact; zero orphans.
- Increment (d) added the FAILING arc (fail→rollback→fix) + a 3-dim clean-slate fingerprint + an arc-helpers.sh refactor. Fired BOTH scenarios (working re-prove + failing prove); BOTH RED — two distinct, understood bugs:
  - BUG 1 (failing arc): the fingerprint's pg_dump returned empty → the centerpiece GUARD fired and refused a vacuous fingerprint (working as designed — NO false-green). Cause = docker-exec pg_dump AUTH (locally the admin user is 'postgres' via local-socket trust and it works — 31k lines; on the VM the admin user needs a password the exec didn't pass). FIX: pass PGPASSWORD in capture_db_fingerprint (arc-helpers.sh). [engineer → architect/foreman review → foreman commit]
  - BUG 2 (working arc): the SECOND upgrade C sat state='scheduled' for 1200s; the daemon never ran it after B completed. Architect diagnosing ROOT CAUSE: real product gap (an unattended box can miss an upgrade scheduled while the service is restarting from the prior one — a genuine Albania hole) vs arc-timing (scheduled C before the post-B daemon was ready). Engineer instrumenting + adding a wait-for-daemon-ready. [architect diagnose → engineer fix/instrument → foreman commit; if a real gap, spawns a product-fix ticket]

KING DOCTRINE (2026-06-18) — the fruition reshape (replaces the old '§9(5)' framing):
1. NO justified residual. Every fake either maps to a real failure a real upgrade can produce (→ reproduce it for real) or it describes a state that cannot occur (→ delete it). If we ever believe a failure is real but can't reproduce it, that's a framework gap to FIX or a misread — never a licence to keep faking.
2. The crashes were ALWAYS real (the migrate path has a complete inject taxonomy: :388 during-migration, :202 mid-tx, :844/:845 after-commit-before-recorded, :911 between-migrations, + stalls). The ONLY fabrication in the whole kill family is fabricate_scheduled_upgrade_row — and its only job is to make ./sb install dispatch. 086's register+schedule produces that 'scheduled' row for REAL. So the reshape is a MECHANICAL swap (fabricate → real register+schedule), family-wide, then delete fabricate. Zero new product code for the crash itself.
3. NOTIFY-HANDSHAKE (King): a test migration runs `NOTIFY chan; SELECT pg_sleep(N);` with NO BEGIN — verified the runner invokes psql without --single-transaction (migrate.go:401), so the NOTIFY autocommits and reaches a listener while the migration sleeps; the listener does a REAL external kill mid-flight. More faithful than the boundary-kill hook (:388, which fires before the migration's SQL runs). Coordination lives in the TEST artifacts → product stays pristine.
4. EXTERNAL-KILL-TIMING (unifying primitive): kill is real; TIMING is by NOTIFY while a migration runs, or by watching logs/process-state otherwise. Retires the in-migration-SQL hooks + the SLOW Go-phase hooks. Residue (small, characterised): the after-commit-before-recorded ~ms window (close via atomic apply+record — see STATBUS-097) and the sub-second Go phases like binary-swap (retry-time, or keep ≤2 minimal hooks).

PLAN (post both-arcs-green): mechanical fabricate→register/schedule swap across the kill family; adopt external-kill-timing; delete the subsumed scenario (the failing arc already covers deterministic-error); retire the in-SQL hooks where the handshake reaches; delete fabricate at zero callers (= the final success criterion). Sketch: tmp/engineer-071-step5-plan.md; the architect's reconciliation map has the per-point detail.

NEW REQUIREMENTS surfaced by the King (separate tickets): STATBUS-095 (12h migration timeout-kill), STATBUS-096 (OOM + timeout kill-recovery tests), STATBUS-097 (scope atomic apply+record to close the residue window).

WORKING ARC GREEN (no-wait, on the 098 fix) — run 27807092720 SUCCESS (2026-06-19): install A → B applied V (claimed t+69s) → C re-stamped (H_B→H_C=297fcce262) → PASS, data intact, ZERO orphans. Confirms the masking-wait removal caused NO regression (the working arc + re-stamp work without it). AC#1 met. [This run claimed via the live NOTIFY (daemon was listening, LISTEN backends=1); the DETERMINISTIC no-NOTIFY proof is the claim-without-notify scenario, firing after the failing arc.]

BUG-1 (failing-arc fingerprint empty, failed twice) ROOT-CAUSED + FIXED: not auth — raw `docker ps|grep -db|docker exec` was fragile as the VM user; replaced with the PROVEN `docker compose exec -T db pg_dump` path + self-diagnosing DIAG. Part-3 durable guards committed too: funcBody wiring test (cli/internal/upgrade/scheduled_claim_wiring_test.go, fast every-CI) + claim-without-notify-arc.sh (non-default deterministic no-NOTIFY scenario). Commit 9452f2cf0 (architect-approved). The 098 product fix is 054c371c6.

NOW: failing arc firing (run 27807756274) — the BUG-1 VM oracle + the clean-slate-after-rollback centerpiece (AC#2). Then claim-without-notify (the 098 no-NOTIFY deterministic proof). OVERNIGHT NOTE: a gh-status glitch hung a monitor ~7h (failing run actually finished 22:13); monitors are now conclusion-based + capped.

FAILING ARC GREEN — AC#2 met (run 27811604893, 2026-06-19, foreman autonomous drive). The CLEAN-SLATE-AFTER-ROLLBACK CENTERPIECE is PROVEN on a real VM: install A → B's V_fail → autonomous rollback to state='rolled_back' (t+76s) → ✓ clean-slate fingerprint matches (post-rollback == post-A, byte-identical: schema+ledger+data) → C applied V_fixed FRESH (recorded once, no re-stamp, no amendments.tsv — the FEW-who-failed half) → PASS, data intact, healthy, ZERO orphans. This is the framework's UNIQUE VALUE — recovery-correctness end-to-end that no fabrication can test.

The failing arc took 5 VM runs to harden the fingerprint (each a test-harness issue, NOT a product/recovery bug — the rollback was always byte-faithful, proven by ledger+data matching throughout): BUG-1 ×3 (pg_dump auth red-herring → the real cause: a giant inline bash -c didn't survive VM_EXEC's printf-%q+sudo-i → restructured to separate reads + runner-side strip), schema-dim worker-partition quiesce (the diff instrument disproved the worker-timing hypothesis), and the pg_dump-18 \restrict/\unrestrict random-nonce strip (the diff instrument named it decisively). Commits: 5eb27898e (quiesce), 6ad1a9b78 (restrict-strip, runner-side anchored).

BOTH ARCS NOW GREEN: AC#1 (working re-stamp, run 27807092720) + AC#2 (failing clean-slate, run 27811604893). The 098 product fix (the framework's first real catch) is fixed + VM-proven. NEXT: the §9(5) reshape (AC#3 fabricate→register/schedule swap family-wide + AC#4 delete fabricate) = the charter fruition; + the deferred polish (comment precision + the ≤90s fast-fail assert).

§9(5) 5a GREEN (run 27813204057, 2026-06-19) — the KILL-ARC DRIVER is proven on a real VM. doc-016 (architect) is the implementable 5a-5e plan. KEY design correction: every CAT-C scenario ALREADY uses a real inject class (:388/:202/:911/:844) — the engineer's 'no mid-migrate KillHere → must fabricate' premise was wrong; so the whole kill family is a UNIFORM mechanical swap (the crash was never the fabricated part — only the scheduling is faked). Commit 62ff41573: NEW helpers arc_schedule_daemon_down (stop daemon + real ./sb upgrade schedule = persistent daemon-down 'scheduled' row, replacing fabricate_scheduled_upgrade_row) + arc_install_dispatch_with_inject (./sb install + STATBUS_INJECT_AT → real crash at the product inject point) + arcs/preswap-checkout-kill-arc.sh (reshaped legacy 2-preswap-checkout-kill: real inject killed-by-system-during-preswap-checkout + real register/schedule; architect-verified every crash-shape + convergence assert preserved). PASS: real crash → recovery → abort to A → data intact, NRestarts=0, ZERO orphans. PHASING: 5b (CAT-A ×4) → 5c (CAT-B ×6) → 5d (CAT-C ×4 + delete deterministic-error + checkout-kill-legacy + assess worker-ddl) → 5e (DELETE fabricate at zero callers = AC#3+AC#4). VM-prove depth (each scenario vs representative-per-category + final full-suite) = architect's call (pending). Engineer building 5b.

§9(5) PROGRESS (2026-06-19, foreman autonomous drive). 5b CAT-A COMPLETE (5/5 reshaped onto the kill-arc driver, fabricate→register/schedule): checkout-kill (5a, run 27813204057), backup-kill + binary-swap-kill (batch-1, 8abe52140), container-restart-kill (b216e1086), rollback-kill (deterministic, e96ed2a34 + error-assert a64ce8f6d). rollback-kill DETERMINISTIC GREEN (re-VM 27816903271): the methodology demonstrated end-to-end — architect contract-review caught the STALE legacy both-outcomes model → observational VM-prove (the run is the oracle) revealed C9 FIRES (disproving the no-C9 hypothesis) → architect reconciled + OWNED the error (recoveryRollback service.go:2174 WRAPS d.rollback :2271→:5461→:5646 KillHere, UNCONDITIONAL; PreSwap reaches d.rollback unconditionally; the ':954 DB not modified' is the restoreDatabase no-op, NOT a skip) → deterministic outcome-B rewrite, VM-confirmed (C5 wedge 137 PreSwap → C9 137 :5646 → rolled_back, 'pre-swap, before binary-swap commit boundary'). Real deterministic C9 coverage; no net-new wedge. Plus a product comment-fix (service.go:5637-5644, the misleading 'C9 non-deterministic' — true only for the Resuming reach-path; 6fc96ce70). 5c CAT-B stall mechanism committed (a15add31b: arc_install_stall_dropin restart-for-env + the anti-false-pass still-in_progress gate); C15 (postswap-watchdog-reconnect) FIRING (27817729943) = the NEW stall-mechanism VM-prove. CAT-B tiered (engineer pre-read): 2 easy ride C15's stall (no VM); rollback-restore-watchdog (2-step); 2 harder = NEW mechanisms (resume-died-rollback kill-via-dropin 4th sub-variant; archivebackup-resume rollback-recomplete delta=1) → each a design-pass + VM-prove. NEXT: C15 green → the tiered CAT-B → 5d (CAT-C mid-tx :202 + after-commit :844 + shared-fixture construct refactor + matrix mode) → 5e (parallel matrix full-suite + DELETE fabricate = AC#3+AC#4).
<!-- SECTION:NOTES:END -->
