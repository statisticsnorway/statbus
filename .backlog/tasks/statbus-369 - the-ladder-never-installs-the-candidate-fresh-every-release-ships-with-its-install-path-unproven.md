---
id: STATBUS-369
title: >-
  the ladder never installs the candidate fresh: 0-happy-install installs the
  previous stable, so every release ships with its own install path unproven
  (v2026.09.0 fresh install fails)
status: In Progress
assignee: []
created_date: '2026-09-14 12:36'
updated_date: '2026-09-15 06:56'
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
