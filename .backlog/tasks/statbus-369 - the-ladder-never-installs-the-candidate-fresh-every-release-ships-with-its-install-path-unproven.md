---
id: STATBUS-369
title: >-
  the ladder never installs the candidate fresh: 0-happy-install installs the
  previous stable, so every release ships with its own install path unproven
  (v2026.09.0 fresh install fails)
status: In Progress
assignee: []
created_date: '2026-09-14 12:36'
updated_date: '2026-09-15 13:33'
labels:
  - release
  - install
  - fail-fast
dependencies: []
priority: high
type: bug
ordinal: 1
---

## The finding (observation, 2026-09-14)

`doc/release-ladder.md` line 21 says smoke `0-happy-install` proves "a fresh
Ubuntu VM runs the real install.sh and ends with a healthy StatBus **at the
candidate**". The script says otherwise, in its header and its code:

    # Fresh VM → install the newest stable release strictly below the target
    INSTALL_VERSION="${INSTALL_VERSION:-$(select_release_baseline_from_repo "$REPO_ROOT")}"
    install_statbus_in_vm "$VM_NAME" "$INSTALL_VERSION"

No scenario in `test/install-recovery/scenarios/` installs the candidate
itself (`grep commit_under_test scenarios/` finds nothing). Both smoke cells
start by installing the previous stable. So by induction: **every stable
release ships with its own fresh-install path unproven**; it is first
exercised when the NEXT candidate's ladder installs it as the baseline.

Log lines that show it (verbatim):

- rc.14 (green, 2026-09-04, install-recovery-harness job 0-happy-install):
  `Release selected for clean install: v2026.08.1` ...
  `Detected install state: half-configured (current=v2026.08.1, target=v2026.08.1)` ... `✓ health check passed`
- rc.04 (red, 2026-09-14, test-smoke run 34840110574):
  `Release selected for clean install: v2026.09.0` ...
  `Detected install state: fresh (current=v2026.09.0, target=v2026.09.0)` ...
  `[4/17] Configuration FAILED: .env.config not found`

So v2026.09.0, stable since 09-04 and running on Norway and Albania (both
by upgrade, never fresh), fails a fresh install on a harness-prepared box.
Whether that is a v2026.09.0 bug or the candidate's harness no longer
delivering `.env.config` is being split by one VM (hatchling, protocol in
`tmp/v20260900-fresh-install-investigation.md`).

Why it was missed: the scenario never asserted "installed version == the
candidate". A proof names its claim in an assertion, not in a comment.

## Work

1. **Cause** (in flight): VM observation, then either a fix in the candidate's
   install path (if v2026.09.0 has the bug, the candidate must not) or a
   harness fix.
2. **`0-happy-install` installs the candidate.** From the candidate's own
   release assets (`sb-linux-<arch>` at the tag, published images at the
   commit), via the real `install.sh`, on a fresh VM. Assert, in the
   scenario: `sb version` on the box equals the candidate tag; `public.upgrade`
   records the candidate; health passes. `0-happy-upgrade` keeps installing
   the previous stable (that IS its claim).
3. **Doc and code agree.** `doc/release-ladder.md` row 4 stays; the scenario
   header is rewritten to match. `install-works` in STATBUS-359's naming is
   this cell.
4. **`release covered` must not ride this cell across a version change**: a
   fresh install of X is evidence about X only.
5. Adversarial review; then this candidate's ladder runs the new cell and
   the fix together.

## Done when

The rc ladder for this batch shows `0-happy-install` installing the
candidate tag on a fresh VM and passing, and `0-happy-upgrade` installing
v2026.09.0 then upgrading to the candidate and passing. Both observed in
run logs and recorded here. A fresh `install.sh` of the resulting stable on
a clean box works (the next ladder's baseline hop confirms it, and so does
step 2 at that time).

## Cause (observed on one VM by hatchling, 2026-09-14 12:36; `tmp/v20260900-fresh-install-investigation.md`)

**Harness, not v2026.09.0. Production is not exposed.** `cf6e30c6f` (09-07,
STATBUS-341 review fix "token-bearing file must be 0600") changed the upload
from `chmod 0644 /tmp/env-config` to `chmod 0600`. The file is uploaded as
root; the generated install script runs as `statbus` and does
`cp /tmp/env-config .env.config 2>/dev/null || true`. A root:root 0600 file
is unreadable to `statbus`, the copy failed silently, and v2026.09.0's
install correctly reported "fresh, no .env.config". Reproduced with a direct
probe on the box; VM deleted. rc.14 (09-04) predates the chmod change,
which is why it was green.

Two process lessons, both now pinned by `tests/release-baseline-test.sh`:
the reviewer asked for 0600 and nobody asked who reads the file next; and
the one line that delivers the box's config was allowed to fail silently.

Fix `01ab18349`: `chmod 0600 && chown statbus:statbus` in one remote
command (both properties or neither), and the two copies in the generated
install script fail loud with the reason (exit 70). Test forbids the silent
form.

Remaining in this ticket: step 2 (0-happy-install installs the candidate,
wyvern, in flight), steps 3-4, review, rc.05.

## Product gap and rulings (2026-09-14 12:53-13:03)

Rebuilding the cell on install.sh's real fresh path hit a product gap
(tigress, stop-and-report): `install.sh:497-500` deletes a non-git
`~/statbus` before cloning, so nothing can be pre-placed; a pre-clone makes
line 580 take the RESCUE branch; `--non-interactive` is rejected. The fresh
path could only ever be driven by a human at the four prompts. That is why
the harness hand-rolled its own install in May.

Owner rulings, in order asked:
1. Unattended seam = ONE env var `STATBUS_ENV_CONFIG=<path>`, read by
   install.sh, passed through to `./sb install`; `--non-interactive` passes
   through.
2. Actionable fail-fast: the file must contain exactly the keys the
   interactive prompts ask, all of them, nothing extra; missing/extra keys
   named with the prompt text; `--non-interactive` without the var lists the
   required keys. One table feeds prompts and validation; a test asserts they
   are the same set.
3. Refusal applies only when a fresh `.env.config` would be created;
   existing configs are never questioned (recovery/fixup unaffected).
4. Exact prompt keys only (mode, domain, display name, slot code);
   `DEPLOYMENT_SLOT_PORT_OFFSET` stays fixed output. Defaults are the NSO's
   sensible answers and are not asked. Channel, role, URLs, debug are set
   after install via the operator path (edit, `config generate`, restart);
   the harness does the same, as a second labelled phase.

For this candidate `0-happy-upgrade`'s baseline hop stays hand-rolled
(v2026.09.0 has no seam); it switches to install.sh from the first stable
carrying the seam. Documented in the scenario header.

## Scope grew into product correctness (2026-09-14 13:45-14:12, owner + tigress + Luna)

Owner-console review of the seam surfaced and ruled, in order: the trust
username belongs in the answer file (`TRUST_GITHUB_USER` as a fifth key,
persisted as `UPGRADE_TRUSTED_SIGNER_<user>`; the flag stays a compatibility
input with conflict refusal); optional `STATBUS_INSTALL_VERSION`; and a
product `sb service restart` for the post-install config change, because
the unattended path had nothing to restart with.

The restart went through Luna (bonehound) on the dirty scratch tree:
REJECT on a P1 (releasing the mutex before starting the daemon left a window
where a concurrent `sb install` could probe a DB still coming up after
compose down/up), then ACCEPT after: daemon started under the held mutex
(`Type=notify` returns only after DB connect/LISTEN, so no admission
window); an explicit retained restart marker on start failure with install
refusing before Detect and `sb restart all` as the retry; restart markers
exempted from `recoverFromFlag`'s automatic unlink (a real daemon defect
found on the way); a cross-process lock-contention test. All shell suites,
discovery and ShellCheck green against `df6727be4`.

Consequence for the ladder: rc.05 carries a new daemon-adjacent code path
no VM has run. Watch the smoke logs for the restart step specifically.
Commits pending tigress's final green run.

## rc.05 (2026-09-14 15:09, `13074fdd8`): admitted, both smoke cells red, different causes

Run 34860298572. Cut unattended under the owner's 14:25 authorization after
Luna whole-branch ACCEPT (`tmp/STATBUS-369-review/whole-branch-review-r2.md`)
and two CI reds fixed on the way (errcheck in the new restart test;
golangci-lint download 504, now retried).

`0-happy-upgrade` (baseline hop, hand-rolled v2026.09.0 install): never
reached the product. `curl -fsSL` of the release asset got HTTP 504 five
times. Also a harness defect from `df6727be4`: the fail-loud diagnostic
`$(ls -l /tmp/env-config 2>&1)` exits 2 when the file is absent and `set -e`
kills the script before the message prints (`rc=2 at vm-bootstrap.sh:1284`).
Fix: retry/backoff on the asset download; `|| true` inside the diagnostic.

`0-happy-install` (candidate, REAL install.sh --version on the fresh path,
private mode): admitted, steps 1-7 green (first time any RC has passed
step 4 on a harness box), step 8 `docker compose up -d` failed:
`container statbus-test-db is unhealthy` (healthcheck pg_isready, 5s x 10).
No DB log captured: the support bundle stays on the VM and the harness
reaps it. Cause open; two hypotheses, not guessed between: private-mode
generated config the DB rejects, or a cold CX23 needing >50s for first
Postgres start + seed restore. Certain fix regardless: the support bundle
includes `docker compose logs db` on a step-8 failure, and the harness
copies the bundle off the box before reaping.

## rc.05 step 8 cause, observed on one VM (sunflower, 15:36; `tmp/rc05-step8-investigation.md`)

Neither hypothesis. PostgreSQL crash-looped from the first start:
`could not open configuration file "/etc/postgresql/postgresql.conf":
Permission denied`. On the box every tracked file was 0600/0700
(`postgres/postgresql.conf`, `pg_hba.conf`, `start-postgres.sh`, ...):
the fresh wrapper in vm-bootstrap.sh set a bare `umask 077` for the
answer-file write and never reset it, so the product's own `git clone`
inherited it. An NSO's shell is umask 022; the harness imposed its hygiene
on the product. pg_isready never succeeded in 190 s.

Fix `d888ea443`: umask scoped to the answer file in a subshell, and the
wrapper asserts umask 022 before invoking install.sh (fails loud, exit 70).
Same commit: asset download retries 8x20s (rc.05 baseline hop lost to five
504s), and the fail-loud `ls -l` diagnostics carry `|| true` so `set -e`
cannot kill the message (rc=2 at :1284 in rc.05). Support-bundle capture of
`docker compose logs db` + copy-off before reap: hibiscus, in flight.

Same family as the 0600 env-config bug that started this ticket: the
harness sets a permission for its own secret and the next reader cannot
read. Both now pinned by assertions in the wrapper.

## rc.06 and rc.07 (2026-09-14 15:51 and 20:05; overnight under the owner's authorization)

rc.06 (`59c4a179b`): `0-happy-upgrade` PASS (v2026.09.0 installed, upgrade
service took the box to the candidate in 109 s, data intact). `0-happy-install`
red on the coordinator's own guard: it asserted umask value `022`; Ubuntu's
user default is `0002`. Fixed `61ff72845` (guard checks the property
"other-read kept", refuses only `*[4567]`).

rc.07 (`61ff72845`), orchestrator 34890758645: **both smoke cells PASS**
(`0-happy-install`: candidate installed on a fresh box via the real
`install.sh --version`, private mode, all steps, version/row/health asserted)
and **dev canary PASS**. Install Recovery Harness (run 34892634113): 8 of 10
scenarios pass, 2 red:

- `3-postswap-worker-ddl-deadlock`: `rc=127` at line 200,
  `quiesce_upgrade_service` undefined. Harness debt: b04204b1c (09-06) deleted
  ~250 lines of wedge-helpers incl. this function but left this caller. Bash
  resolves function names at call time, so no static check caught it; it
  surfaced an hour into a VM run. Fixed `518831ff7` (rose): helper restored
  with its invariant, plus a test that sources every lib and every scenario
  and `declare -F`-resolves every lib call, so a deleted helper fails offline.
- `1-boot-concurrent-install`: the first `./sb install` (with the migrate-up
  stall injection) did not reach the stall in 300 s; `upgrade-in-progress.json`
  never appeared. Its own output (`/tmp/install-c10-first.log`) stayed on the
  reaped VM. Cause open: maple on one VM with KEEP_VM=1 capturing that log.
  Passed at rc.14; since then the candidate's install path changed (369 seam,
  restart marker, pre-Detect refusal), so product is a live suspect.

Owner correction recorded: v2026.09.0's ladder was green on 09-04; what was
wrong then was ONE cell's claim (the smoke installed the previous stable, not
the candidate). "Green for the first time" is false; "the candidate cell now
proves what the doc always said" is the accurate statement.

Owner requirement (2026-09-15 06:55): log capture on failure must be
systematic across every scenario, not per-scenario addenda. Every process
the harness starts on a VM writes to a known path; on ANY failure the
harness copies every such log off the box before reaping, and the job log
names them. Filed as the next item under this ticket.

Upgrade Arc Harness was skipped (chain stopped at 4/5).

## rc.08 and rc.09: concurrent-install proof still blocked (2026-09-15 12:11 UTC)

rc.08 (`d4ef99c32`), orchestrator `34944448612`: smoke and dev canary
passed. Recovery run `34945893389` passed 13 of 14 scenarios, including
`3-postswap-worker-ddl-deadlock`. Only `1-boot-concurrent-install` failed.
The stall-readiness helper passed a multiline command to `VM_EXEC`, whose
guard rejects that transport; the helper discarded the diagnostic. The
previously green rc.14 job also logged a readiness timeout, then continued
to the second-install refusal and first-install convergence assertions.

Changes `058a776c8` and `476876eb3` attempted to repair the probe with a
single-line command, visible transport errors, and a non-self-matching
`pgrep` pattern. They also changed two other multiline helpers to
`VM_SCRIPT_INLINE` and repaired the failure-capture scp source form.
rc.09 was cut at `476876eb3` after the pre-cut checks passed.

Live check at 12:08 UTC: rc.09 orchestrator `34962753280` has passed smoke
and dev canary. Recovery run `34964519724` is still running, but concurrent
job `104366119867` has failed before launching the second install. No full
ladder acceptance and no Norway-ready candidate are established.

Independent review identified two remaining issues to reproduce and fix:

- `VM_EXEC` warns that even single-line shell bodies containing variable
  expansion can be changed by its `sudo -i` transport. Replacing multiline
  syntax alone was insufficient evidence of a working remote probe. Use
  the documented file-based transport and prove old-fails/new-passes.
- The full failure-capture directory was fetched onto the runner, but the
  workflow's artifact upload glob omits that directory. Capture must survive
  runner disposal, not merely VM disposal.

Evidence correction: `runMigrations` actually spawns the absolute-path
`sb migrate up --verbose` subprocess. A stale comment suggesting otherwise
is not the running implementation. An INJECT marker read in a post-timeout
log tail does not establish when the stall began. A flag absent after EXIT
cleanup does not establish that it was absent during install. Prior claims
about the stall occupying the whole wait window or the product being clean
were unsupported. Product concurrency remains unproved by this candidate
until the scenario reaches and passes its actual concurrent-install checks.

Crocodile owns reproduction, a focused regression test, and the narrow fix.
Cricket independently reviews transport, PID identity/stability, and artifact
upload. Next candidate only after review and the applicable pre-cut gates.
The deferred eight-ticket batch remains deferred until Norway and promotion.

## Product defect reproduced and repaired; next cut pending (2026-09-15 13:05 UTC)

The corrected scratch harness detected a migration process on a fresh VM,
then failed reading the install flag before launching the second installer.
This was a failed exploratory run, not an accepted concurrency proof.

An actual DB-free API regression then established a product defect, without
relying on the ambiguous flag-read failure: hold `AcquireInstallFlag`, call
`RecoverFromFlag`, and observe recovery unlink the live marker. A second
`AcquireInstallFlag` then succeeds while the original flock is still held.
The two descriptors lock different inodes. The stale/free control passed.
Evidence: scratch `tmp/install-flag-red.log`, test
`cli/internal/upgrade/install_flag_recovery_test.go`.

Product repair `510c76e4c` preserves active install ownership and uses locked,
revalidated metadata/inode cleanup for stale flags. Independent real-API
tests cover active exclusion, stale cleanup, restart intent, changed held
metadata and replacement inodes. The focused race suite passed. Harness
repair `1271dc98d` uses file-based observation, intended injection/process
identity, current flock-based holder semantics, checked refusal/completion
and absence assertions, pre-release failure capture and retained artifacts.
All 12 offline harness scripts passed. Cricket approved the nine-file
snapshot; root verified file hashes before and after landing both commits.
These are local/code-review results, not published-candidate VM acceptance.

Go CI `34970946642` then caught an admission-order regression in the new
workflow test step, so rc.10 was NOT cut. Reviewed scratch follow-up
`1c0bbe83e488205bd4ca7cf1b0fa0d92852a628e` moves only that unchanged step
after shared admission, before build and paid operations. The original
STATBUS-350 test reproduces red then green unchanged; full `go test
./cmd/release -count=1 -v` and affected harness tests passed. Cricket's
approved workflow SHA256 is
`e9e985ceb4863a5a8e75fda2ff6f8a1dee84a4c23f3fb5c683c52d8565fe916e`.

Current next step: root lands the reviewed follow-up, pushes, observes
exact-commit CI, runs authenticated `./sb release check`, then cuts rc.10
and drives its actual published-artifact ladder. Do not require that ladder
to pass before publishing the candidate it needs. Prior rc.09 results do
not prove this repaired product. No Norway deployment or promotion yet.

Current handoff and review: `tmp/rc09-crocodile-status.md`,
`tmp/rc09-cricket-review.md`. Both worker-owned exploratory VMs were deleted;
their logs are retained. The earlier cut watcher `491893y2ei` stopped at
12:49 on the Go failure and is not still waiting or publishing anything.

## rc.10 published; real acceptance now running (2026-09-15 13:09 UTC)

Workflow follow-up landed as `bd45f25ce`; exact-commit Images, Go Test and
app CI all passed. Authenticated preflight passed, and
`v2026.09.1-rc.10` was published at
`bd45f25ce309ac7c40e758ec17ecd73ba6f661af`. Root verified both the tag's
commit and its remote ref. The candidate includes the reviewed product
split-lock repair and the corrected fail-closed concurrency proof.

Orchestrator `34973239226` is running. Next required evidence is its real
published-artifact ladder, especially actual second-install refusal and
first-install completion in the recovery scenario, followed by the arcs.
No full-ladder success or Norway readiness is claimed yet. Root read-only
watcher `844501zbx2` is bounded and wakes on completion; no foreground wait.

Current files: `tmp/rc10-target-sha.txt`, `tmp/rc10-release-check.log`,
`tmp/rc10-cut.log`, `tmp/rc10-published-tag.txt`, `tmp/rc10-orch-id.txt`,
`tmp/rc10-orchestrator.json`, and `tmp/rc10-ladder-watch.log`.

## rc.10 recovery underway; provisioning failure (2026-09-15 13:33 UTC)

Live checks confirmed both smoke cells (`34973357020`), hardening
(`34973239251`), and dev canary passed. Recovery `34975170231` is running.
Its advisory job `104401335484` failed before installation: Hetzner created
server `166053156` but returned `server_error` during start. Workflow cleanup
then deleted that exact server. Saved API job log:
`tmp/rc10-advisory-failed.log`. This is an observed provisioning failure,
not a failed product assertion or a reason by itself to cut another RC.

Concurrent-install job `104401335537` is still running. Seedling is checking
the safe same-candidate retry and orchestrator-continuation path, preserving
admission/fleet ownership and the ongoing matrix. No retry dispatched yet,
no code change, no new candidate. Plan artifact:
`tmp/rc10-provisioning-retry-plan.md` (worker to write). Read-only watcher
`1948400iv2` checks for the concurrent-install verdict without a foreground wait.

Owner instruction (13:33 UTC): let the current run finish, inspect all of
its failures, then restart through the coverage-aware path so passed
scenarios are reused and missing proof runs. If another substantive defect
is exposed, fix it before rerunning. Seedling verified the entrypoint:
wait for BOTH recovery `34975170231` and parent `34973239226` to be terminal,
review all failures, then run
`gh run rerun 34973239226 --failed -R statisticsnorway/statbus`.
The parent recomputes `covered-subset`, retaining successful scenario marks
from the completed failed recovery run. Its fresh child revalidates admission
and the fleet lease, then the parent can proceed to arcs. Do NOT rerun the
child first: failed-only child rerun skips successful discovery/admission.
No overlapping retry or new RC merely for this cloud-start failure.

## rc.10 concurrent-install proof passed (2026-09-15 13:48 UTC)

Published-candidate job `104401335537` PASSED. Captured log
`tmp/rc10-concurrent-install-pass.log` shows the install-held flag, second
invocation refusing with the live-install/lsof diagnostic, first exit 0,
completed HEAD upgrade row, and confirmed absent flag. This establishes the
actual VM concurrency acceptance path, not merely the offline regression.
Stale-flag handoff, startup-timeout, and bool-text regression also passed.
Recovery still has running/queued siblings; parent remains in progress.
No retry dispatched and no full-ladder green claimed.

The separate partial-allocation cleanup gap is reproduced in Seedling's
isolated `rc10-partial-allocation-fix` scratch clone. Mocked prototype tests
are passing, with final controls/review pending. No main product edits,
cloud operations, or change to rc.10 were made for this investigation.

## Same-candidate parent retry launched (2026-09-15 14:12 UTC)

Both original recovery and parent concluded failure. All 12 other scenario
jobs passed, and the final orphan sweep passed. Only advisory-too-early
failed, at the previously captured provider start error before installation.
Verified exact rc.10 SHA/ref/events and newest remote tag, empty fleet group
(documented HTTP404), and authenticated covered-subset exit0 selecting ONLY
`1-boot-advisory-too-early`. Root executed the owner-authorized parent-only
`gh run rerun 34973239226 --failed -R statisticsnorway/statbus` at14:12.
GitHub accepted and parent became queued. No child rerun, source push, or
new candidate. Fresh child admission and actual outcome remain to observe,
then upgrade arcs. Bounded watcher `530775l30k` is active.
Evidence: `tmp/rc10-parent-before-retry.json`,
`tmp/rc10-recovery-before-retry.json`,
`tmp/rc10-recovery-retry-coverage.md`,
`tmp/rc10-recovery-retry-uncovered.txt`, `tmp/rc10-parent-retry-watch.log`.

## Recovery retry passed; arc stage active (2026-09-15 14:28 UTC)

Fresh child `34980128355` passed admission, its sole advisory-too-early
scenario, and final orphan cleanup. Parent attempt2 now records the recovery
stage successful. All 13 selected recovery scenarios have successful proof
across the original run and retry, without rerunning the 12 passed scenarios.
Parent upgrade-arc stage is in progress; no arc child was visible at the
14:27:52 snapshot yet. Full ladder green and Norway handoff remain pending.
Bounded watcher `4786353mw6` tracks dispatch and verdict.

## Two arc failures under investigation (2026-09-15 14:51 UTC)

Arc run `34981937538` has failed jobs `104426200815`
(boot-migrate-churn-alive-idle) and `104426200884` (c-rollback-resurrection).
After-commit-before-recorded-kill passed. Other arcs continue. Root delegated
exact completed-job log triage to Palmtree, without main edits or cloud
operations. No cause or product-clean claim yet, no blind retry or new cut.
Bounded watcher `8812411r50` continues collecting outcomes.
Evergreen separately ACCEPTED the partial-allocation scratch cleanup repair:
15/15 mocked controls pass, original code fails four expected controls.
That fix remains isolated, not landed into this active candidate.

## Arc harness fix independently accepted (2026-09-15 15:14 UTC)

Lead and independent log review attributed the two reds to obsolete harness
expectations: DB-down before C9 despite intentional rollback floor replay,
and a failure-code prefix inside human prose instead of structured failure_code.
Scratch commit `67cc2ba30915ee504a23769902853e0425c47574` corrects those
assertions plus the analogous postswap-health-park assertions. Bat ACCEPTED
actual scenario wiring, fail-closed query/control behavior, preserved C9
boundary and later checks. Regression, syntax, ShellCheck and diff checks pass.
Scratch: `/Users/jhf/ssb/.jcode/scratch/rc10-arc-assertion-fix`.
No landing/push yet. VM acceptance requires the next published candidate.
Current arc run has seven scenario passes, the same two failures, three
running and 23 queued. Let remaining evidence accumulate before the next cut.

## Third red verified as covered assertion drift (2026-09-15 15:52 UTC)

Arc job `104426200927` postswap-health-park failed at its obsolete
HEALTHCHECK_REST_DOWN prose-prefix assertion. Bird verified the exact first
failure against the completed job log and accepted scratch commit67cc2ba30:
this is the same structured-code/prose split already repaired, not a new
mechanism. Evidence: `tmp/rc10-arc-red/postswap-health-park-HANDOFF.md`
and `job.clean.log:4435-4437`. Current35-arc status:15 passed,3 failed,
3 running,14 queued. Reviewed harness fix remains in scratch; no source push
or new candidate until remaining failures are assessed. Monitor545760de6e active.

## Fixes landed on master ahead of next cut (2026-09-15 16:14 UTC)

Owner clarified: land reviewed fixes immediately; only the next candidate
cut waits for full assessment of the previous ladder's failures.

- `01f1cc404` test: fix rc10 arc state assertions (all three arc reds).
- `614e22914` ci: reap own partially created VM when create succeeds but
  start fails (partial-allocation ownership gap).

Both pushed to master at `614e22914`. Offline verification on master:
arc-state regression PASS, 15/15 partial-allocation controls PASS, adjacent
harness tests (happy-install, fresh-installer, scenario-helper-resolution,
run-boundary) PASS, bash -n and diff checks clean. Next candidate is cut
only after the rc.10 35-arc run is terminal and every failure assessed.

## rc.10 arc run final tally (2026-09-15 17:05 UTC)

Run34981937538 complete:33 passed,6 failed,1 skipped. The six are the full
set; no additional mechanism emerged:

- boot-migrate-churn-alive-idle  — C9 DB-state drift        (fixed 01f1cc404)
- c-rollback-resurrection        — failure_code prose-prefix (fixed 01f1cc404)
- postswap-health-park           — failure_code prose-prefix (fixed 01f1cc404)
- restore-broke-reattempt        — flag.step schema-floor drift (fix in progress)
- rollback-schema-floor-failure  — lineage wiring             (fix in progress)
- rollback-schema-floor-adoption — lineage wiring             (fix in progress)

The three remaining are the STATBUS-354 schema-floor family; specialist is
implementing in scratch (read doc/upgrade-rollback-floor.md, product service.go,
workflow lineage resolver) rather than a one-line swap. Parent orchestrator
34973239226 remains in_progress awaiting arc teardown and verdict. Next
candidate is cut once all six fixes are on master.

## All six rc.10 arc failures addressed on master (2026-09-15 18:13 UTC)

Final fix `d3b0c4dea` landed and pushed. It routes rollback-schema-floor-
adoption/failure to the failing lineage with SCHEMA_FLOOR_BASE_SHA=56559fa7
(the exact pre-column parent of 012ca22da), and corrects restore-broke-
reattempt's C9 step assertion from migrate-up to rollback to match the
STATBUS-354 durable StepRollback stamped in restoreAndFinalize (service.go
10520/10586). Downstream recovery_attempts=1 + git-corrupt ABORT oracle
re-derived from product code; no kill boundary or recovery assertion weakened.

Two independent reviewers ACCEPTed (chick authored, cow reviewed). Offline
regression, bash -n, diff check, go ./internal/upgrade, and targeted cmd
tests pass. Master now at d3b0c4dea with all six rc.10 arc failures fixed:

- 01f1cc404 (3 assertion drifts) + 614e22914 (partial-allocation reap)
- d3b0c4dea (schema-floor family: 1 step drift + 2 lineage wirings)

Real VM proof of the two schema-floor arcs is deferred to the next candidate
ladder by design. Ready to cut rc.11 from master d3b0c4dea.

## rc.11 cut and ladder running (2026-09-15 18:23 UTC)

Owner cut `v2026.09.1-rc.11` at `5e51741d12f43033eb3f06376f001714145d9b48`
(all six rc.10 arc failures fixed on master). Release
`35007156214`, Test Hardening `35007156279`, and Fleet Orchestrator
`35007156333` started. Monitoring the published-candidate ladder; the
schema-floor arcs now run against the corrected lineage/assertions. No
green-ladder claim yet.

## rc.11 ladder terminal: 36 pass / 4 fail (2026-09-15 22:07 UTC)

rc.11 (5e51741d1) full ladder: Release/Smoke/Hardening/dev/recovery all
green; 35-arc harness 36 pass, 4 fail. c-rollback-resurrection and
postswap-health-park now PASS (01f1cc404 correct). Four still fail, all
STATBUS-354/347 schema-floor consequences, three distinct root causes:

1. boot-migrate-churn-alive-idle (104534517094) — PRODUCT regression: the C9
   gate now passes (DB running, flag, B row in_progress), but the later
   false-convergence oracle caught the product self-healing the row to
   'completed' after flagless recovery despite the floor-bound broken migration
   being genuinely pending. See tmp/rc11-arc-red/handoff.md (crocodile triage).
2. restore-broke-reattempt (104534520372) — behavior change: the C9 step
   (flag.step="rollback") now passes, but the 6th ABORT dispatch exited 75
   (ROLLBACK INCOMPLETE / degraded, manual recovery) instead of the asserted
   exit 1 (catastrophic git-corrupt ABORT). Needs ruling whether 75 is intended.
3. rollback-schema-floor-adoption (104534520490) — INFRA: SCHEMA_FLOOR_BASE_SHA
   56559fa7 has no published statbus-sb image; install A fails "not found".
4. rollback-schema-floor-failure (104534520572) — same missing-image infra.

Fix work in progress overnight. No blind assertion swaps; #1 is a genuine
product bug to fix in the recovery path, #2/#3/#4 need the correct pre-column
released baseline with a published image plus the intended abort exit code.

## rc.11 root-cause refinement: two product regressions (2026-09-15 22:16 UTC)

Deeper triage shows the restore-broke-reattempt red is NOT a stale harness
assertion but a product regression, and it joins boot-migrate's false
convergence as a second genuine defect, both from STATBUS-354 (66c9d61b6
"reapply daemon floor after snapshot restore"):

- boot-migrate-churn-alive-idle: flagless recovery false-converges the row to
  'completed' when the box is genuinely behind (floor-bound broken migration
  pending). (crocodile triage tmp/rc11-arc-red/handoff.md)
- restore-broke-reattempt: the git-corrupt abort + refusal was lost.
  ErrRollbackGitCorrupt ("ROLLBACK_FAILED_GIT_CORRUPT") is now dead code
  (defined in failure_code.go, zero non-test usage); the "do NOT proceed" /
  "the git tree is corrupt" refusal was removed in 66c9d61b6. The git-corrupt
  case now falls into the generic degraded "ROLLBACK INCOMPLETE" path (exit 75,
  failure_code=null) with no specific actionable refusal.
- rollback-schema-floor-adoption/-failure: SCHEMA_FLOOR_BASE_SHA=56559fa7 has
  no published statbus-sb image; the last pre-column release with a retained
  image is v2026.09.0 (60cb46c2).

All four are STATBUS-354 recovery-safety consequences, not ordinary harness
drift. Fixes must restore the false-convergence guard and the git-corrupt
refusal in the product, and point the floor arcs at a published pre-column base.

## Fix progress (2026-09-15 22:18 UTC)

- Floor-arc image fix ready (scratch 39ba3c3b4): SCHEMA_FLOOR_BASE_SHA → v2026.09.0
  (60cb46c2), the last released pre-column commit. De-risked: cross-version-
  rename-handoff passed in rc.11 using install_statbus_at_sha at 730b5001c
  (rc.05), proving old release images are retained (56559fa7 failed only because
  it is a mid-series commit, not a release).
- false-convergence regression: cricket investigating (product fix).
- git-corrupt regression: dog investigating (product fix).
No cut until both product fixes are reviewed and landed with the floor-image fix.

## Two product fixes ready (2026-09-15 22:32 UTC)

Both STATBUS-354 regressions fixed in scratch, awaiting independent review:

- false convergence: cricket commit 5a59a3cd7 — observed-state migration oracle
  now checks coverage (every on-disk version has a ledger row) not just MAX, so
  a replayed floor cannot conceal a missing lower migration.
- git-corrupt refusal: dog commit 4bd6d1e8b — restores ReattemptRestore's
  pre-destructive resolveGitRestoreTarget guard; a missing pre-upgrade pin now
  refuses with ErrRollbackGitCorrupt + "git tree is corrupt; do NOT proceed"
  and persists failure_code=ROLLBACK_FAILED_GIT_CORRUPT before any destructive
  step, preserving STATBUS-354 target-worktree retention.

Plus floor-arc image fix 39ba3c3b4 (SCHEMA_FLOOR_BASE_SHA → v2026.09.0).
Dove is independently reviewing A+B. Land all three, then cut rc.12.

## rc.12 through rc.15 ladder evidence (2026-09-16)

- rc.12 (`88a8d8ee2`), arc run `35038249248`: 36 passed, 4 failed.
  `e3c589034` fixed the coverage-oracle narration; `5307ec378` fixed refusal
  row semantics, floor hash sourcing, and floor-failure lineage. rc.13 followed.
- rc.13 arc run `35079590161`: 38 passed, 2 failed, both schema-floor arcs.
  `e3ceafe4b` fixed the adoption data fingerprint and durable floor-failure
  code. rc.14 followed.
- rc.14 repeated 38/40 with the same two schema-floor reds. `900cf9d66`
  established that both were harness assertions contradicting the recovery
  contract: backup retention is deliberate, and the marker phase is
  hyphenated. Independent review ACCEPTed the change.
- rc.15 (`23b3993ad`) was cut after seed-cache recovery work. Arc run
  `35128438594` died before scenarios: Discover succeeded, then fixture/image
  construction hit a Go toolchain CDN TLS timeout because `dev.sh` ignored the
  prebuilt `sb` image. A direct arc-child rerun was then refused by admission,
  correctly, because it bypassed the orchestrator. Orchestrator re-dispatch
  `35141712346` stopped at dev-canary run `35141864469`: re-offering the same
  tag was read as superseded.
- Harness hardening `1eccca23e` makes `sb` procurement git-gated, labels
  infra/admission outcomes, and makes `ops/ci-deploy-status.sh` idempotent on
  `completed_at`. Independent review ACCEPTed it, including mutation control.
  rc.16 is to be cut from this commit by worker whale.

No rc.15 scenario result exists. The next acceptance evidence is rc.16 reaching
its arc matrix and proving the two schema-floor scenarios under `900cf9d66`.

## rc.16 pre-cut gate repairs (2026-09-16 21:20 UTC)

No rc.16 tag exists yet. Exact-commit validation of `1eccca23e` exposed two
pre-cut defects: admission read absent `CANDIDATE_REF` under `set -u`, and `sb`
procurement/build status polluted stdout consumed by niue's postgres-variable
`eval`. Fix `ec8eb39a7` repaired both. Its Go run `35149786323` then found a
deterministic label-coupled harness validation test; `81a9e39f4` made that test
locate the authoritative step by runner command. Go run `35150754066` is green;
Fast Tests `35151057099` and pg_regress `35151057030` remain in progress. No
candidate cut and no arc scenario evidence yet.

## rc.16 pre-cut validation green (2026-09-16 22:05 UTC)

No rc.16 tag exists. The repaired head `81a9e39f4` completed all named pre-cut
checks: Go `35150754066`, Fast Tests `35151057099`, pg_regress `35151057030`,
Images `35150753957`, and app `35150754001` are green. Arc scenarios have not
started because no candidate has been cut.

## rc.16 cut and ladder running (2026-09-16 22:47 UTC)

Owner cut `v2026.09.1-rc.16` at `b8bdf090f` at 22:26 UTC, two
backlog-only commits past green product head `81a9e39f4`. The cut used current
master after verifying an empty non-`.backlog` diff. Release `35157700398`, Test
Smoke `35157807530`, Test Hardening `35157700421`, and dev canary
`35159028395` are green. Fleet Orchestrator `35157700377` is running and has
dispatched Upgrade Arc Harness run `35159276681`; the arc run is in progress.
No scenario tally yet.

## rc.16 recovery stage entered scenarios (2026-09-16 22:51 UTC)

Install Recovery run `35159276681` completed discovery and entered its matrix:
3 scenarios running, 10 queued, 0 terminal. Fleet Orchestrator `35157700377`
remains in stage 4/5. Upgrade Arc has not been dispatched, so its scenario tally
is still unavailable.

## rc.16 recovery matrix running scenarios (2026-09-16 23:33 UTC)

Install Recovery run `35159276681` has reached and run scenarios: 11 pass,
0 fail, 2 running (`5-install-stage-d-advisory-zombie` and
`5-install-stage-e-worker-busy`). This is the first rc.16 evidence that the
`1eccca23e` + `ec8eb39a7` + `81a9e39f4` harness path gets past discovery and
fixture/image construction. Fleet Orchestrator `35157700377` remains in stage
4/5; Upgrade Arc has not yet been dispatched.

## rc.16 recovery green; Upgrade Arc started (2026-09-16 23:36 UTC)

Install Recovery run `35159276681` completed 13/13 scenarios green. Fleet
Orchestrator `35157700377` advanced to stage 5/5 and dispatched Upgrade Arc run
`35162992033`. Arc discovery passed and fixture/image construction is running;
no arc scenario has started, so the arc tally is 0 terminal.

## rc.16 Upgrade Arc reached and running scenarios (2026-09-17 00:18 UTC)

Upgrade Arc run `35162992033` passed discovery, fixture construction, and the
A/B/C image wait, then entered its 35-scenario matrix. Current job tally: 7
pass, 0 fail, 3 running, 25 queued. This is the evidence rc.15 never produced:
the hardened harness reached and ran paid arc scenarios rather than dying in
pre-scenario infrastructure. Fleet Orchestrator `35157700377` remains in stage
5/5 pending the arc result.

## rc.16 Upgrade Arc progress (2026-09-17 00:22 UTC)

Run `35162992033` now has 8 pass, 0 fail, 3 running, 24 queued. Both
schema-floor scenarios remain queued; no triage commit exists because no
scenario has failed.

## rc.16 Upgrade Arc progress (2026-09-17 01:04 UTC)

Run `35162992033` now has 17 pass, 0 fail, 3 running, 15 queued. Both
schema-floor scenarios remain queued. Fleet Orchestrator `35157700377` remains
in stage 5/5; no failure or triage commit exists.

## rc.16 Upgrade Arc progress (2026-09-17 01:07 UTC)

Run `35162992033` has 20 pass, 0 fail, 3 running, 12 queued. Both schema-floor
scenarios remain queued. No failure or triage commit exists.

## rc.16 Upgrade Arc progress (2026-09-17 01:49 UTC)

Run `35162992033` has 29 pass, 0 fail, 3 running, 3 queued. Both
`rollback-schema-floor-adoption` and `rollback-schema-floor-failure` are now
running. No failure or triage commit exists.

## rc.16 Upgrade Arc terminal: 33 pass / 2 fail / 0 skipped (2026-09-17 02:22 UTC)

Upgrade Arc run `35162992033` completed its 35-scenario matrix: **33 passed,
2 failed, 0 skipped**. Failed scenarios:

- `rollback-schema-floor-adoption` — **harness assertion drift**. Exact failure:
  `✗ progress log missing: database container`. The same job had already observed
  `state='rolled_back'`, absent upgrade flag, HTTP 200 health, matching demo-data
  counts, drained worker queue, and no orphan backups. Product log wording is now
  `Starting only the restored database for schema-floor replay ... healthy`, so
  the assertion's literal `database container` needle is stale.
- `rollback-schema-floor-failure` — **product bug**. Exact failure:
  `✗ rest is running`. Immediately beforehand the product correctly recorded
  `ROLLBACK_SCHEMA_FLOOR_FAILED`, said application services remain stopped, kept
  maintenance/read-only active, and exited 75. Nevertheless the scenario's exact
  `docker compose ps --status running --services` check found `rest` running.
  This contradicts the held-closed contract and the product's own diagnostic.

Discovery, fixture construction, image wait, final orphan-VM sweep, and branch
teardown all succeeded, so this was not an infrastructure death and no retry was
dispatched. Fleet Orchestrator `35157700377` concluded failure solely at stage
5/5 because the arc child failed; smoke, dev canary, and Install Recovery (13/13)
were green.

## rc.16 two-red triage landed (2026-09-17 02:38 UTC)

Triage fix `5dbc8d243` landed for both rc.16 reds. It updates the adoption arc to
the exact emitted progress line. For the product red, it starts the existing
proxy container directly so Compose cannot pull `rest` through `depends_on`,
verifies app/worker/rest remain stopped, and durably routes any live-client
violation to `rollback-clients-live` with
`ROLLBACK_FAILED_SERVICES_NOT_STOPPED` before source restore or full-stack
startup. Exact-commit CI is running; no next candidate has been cut.

## schema-floor fix validation checkpoint (2026-09-17 03:24 UTC)

Fix `5dbc8d243` has green Go `35175163025`, app `35175162990`, Images
`35175162978`, and Fast Tests `35175404663`. pg_regress `35175404641` remains
in progress. No rc.17 tag exists and no new paid ladder has started.

## rc.17 pre-cut validation green (2026-09-17 03:32 UTC)

Fix `5dbc8d243` completed every named pre-cut gate green: Images
`35175162978`, Go `35175163025`, app build & lint `35175162990`, Fast Tests
`35175404663`, and niue pg_regress `35175404641`. The Fast Tests and
pg_regress children were concurrency-cancelled once and their single permitted
reruns both passed. No rc.17 tag exists and no new paid ladder has started.

## rc.17 cut; release ladder started (2026-09-17 03:37 UTC)

Cut exact tag `v2026.09.1-rc.17` at `0cefa2fd7913fb3d0fb2b2cd4706d67786ed5451`,
four backlog-only commits past product fix `5dbc8d243`. The first release attempt
had the exact gate refusal `✗ images has not run for 0cefa2fd7913`; manually
triggered Images run `35178601773` passed, then the release pre-flight passed
and pushed the tag. Release `35178846674`, Test Hardening `35178846602`, and
Fleet Orchestrator `35178846600` are queued. Smoke, dev canary, Recovery, and
Upgrade Arc have not started.

## rc.17 Release, Smoke, and Hardening green (2026-09-17 03:56 UTC)

Release `35178846674`, Test Smoke `35178929396`, and Test Hardening
`35178846602` are green. Fleet Orchestrator `35178846600` completed stage 1/4
smoke green and entered stage 2/4 dev canary. Recovery and Upgrade Arc have not
started.

## rc.17 dev canary green; Recovery started (2026-09-17 04:01 UTC)

Dev canary run `35180048644` is green. Fleet Orchestrator `35178846600`
advanced to stage 4/5 and dispatched Install Recovery run `35180198706`, which
is in progress. Upgrade Arc has not started.

## rc.17 Recovery reached scenarios (2026-09-17 04:10 UTC)

Install Recovery run `35180198706` passed discovery and entered its matrix:
3 scenarios running, 10 queued, 0 terminal. Upgrade Arc has not started.

## rc.17 Recovery green; Upgrade Arc started (2026-09-17 04:48 UTC)

Install Recovery run `35180198706` completed all 13 scenarios green. Fleet
Orchestrator `35178846600` advanced to stage 5/5 and dispatched Upgrade Arc run
`35183316509`. Arc scenario discovery and setup are in progress; no arc scenario
has started and the scenario tally is unavailable.

## rc.17 Upgrade Arc reached scenarios (2026-09-17 04:54 UTC)

Upgrade Arc run `35183316509` passed discovery, fixture construction, and the
A/B/C image wait, then entered its 35-scenario matrix. Current scenario tally:
0 pass, 0 fail, 3 running, 32 queued. Both schema-floor scenarios are queued.

## rc.17 Upgrade Arc progress (2026-09-17 05:41 UTC)

Upgrade Arc run `35183316509` has 10 pass, 0 fail, 2 running, 23 queued.
Both schema-floor scenarios remain queued; no failure or triage commit exists.
