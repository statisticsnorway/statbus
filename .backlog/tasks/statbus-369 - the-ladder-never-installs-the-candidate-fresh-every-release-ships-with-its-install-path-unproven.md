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
