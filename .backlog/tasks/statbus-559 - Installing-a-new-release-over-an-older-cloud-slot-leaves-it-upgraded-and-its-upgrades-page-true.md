---
id: STATBUS-559
title: >-
  Installing a new release over an older cloud slot leaves it upgraded and its
  upgrades page true
status: In Progress
assignee: []
created_date: '2026-11-02T15:12:00Z'
updated_date: '2026-11-03T16:42:00Z'
labels:
  - bug
dependencies: []
priority: high
type: bug
ordinal: 482204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: ./cloud.sh install <slot> <stable> over any older slot completes the upgrade, and the admin upgrades page afterwards shows only the truth: no obsolete parked attempts, no false warnings.

Found 2026-11-02 installing v2026.11.0 on niue cloud slots ug and ma (logs tmp/cloud-install-ug.log, tmp/cloud-install-ma.log).

1. ug (schema v2026.09.0, last migration 20260901212308): ./sb install stopped in state detection: 'query reattemptable restore: column rollback_finish_pending_at does not exist' (added by migration 20260907120000, first in v2026.09.1). The pre-migration state probe (cli/internal/install/state.go QueryReattemptableRestore) assumes the current schema. mw and ua have the same schema and would fail the same way. The message says 'nothing was changed' but install.sh had already swapped sb and checked out v2026.11.0. The gate never installs a candidate over a v2026.09.0 database.
2. ma: the v2026.10.5 row stays parked after v2026.11.0 installed successfully. Installer success bookkeeping (cli/cmd/install.go, STATBUS-452) retires unparked interrupted attempts only. Owner decision 2026-11-02: a successful install supersedes parked attempts for older releases too, keeping the park reason and error as history.
3. ma: the page warns 'The upgrader is installed but not running' while it runs. Install stamps unit_floor_state at 14:21:12 before the deferred service start at install exit, and the service restamps only on its 6-hour poll tick.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Install state detection works on every schema the installer accepts: on a database without rollback_finish_pending_at it proceeds (no rollback can be pending there). A test runs the probe against a schema lacking the column, red before the fix and green after
- [x] #2 A gate scenario installs the candidate with install.sh --version over a real v2026.09.0 box and the install completes; red against v2026.11.0, green with the fix
- [x] #3 When ./sb install stops after install.sh swapped the program and checked out the target, the message says what was changed instead of 'nothing was changed'
- [x] #4 A successful install supersedes parked in_progress attempts for other commits; the row keeps its error and park reason and the state log records the transition. The 452 live install test covers it, red before and green after
- [x] #5 The upgrade service stamps unit_floor_state when it starts, so a page read right after a successful install shows no 'not running' warning. Covered by a test
- [ ] #6 ug, mw and ua reach the stable release with ./cloud.sh install, ug's statbus-maintenance belongs to statbus_ug afterwards, and ma's v2026.10.5 row shows superseded
- [x] #7 Found on the manual box 2026-11-02 with v2026.11.0: install.sh refuses root before any lock, download or checkout, with the same sentence ./sb install prints (TestInstallShRefusesRootBeforeAnyWork red before, green after); a fresh install names the checked-out commit (fresh-installer-test red 'commit )' before, green after); the manual-box guide gives the country answers (United Nations / un, TestUnitedNationsIsAnAcceptedInstallationCountry); the questionnaire shows the answers and lets the operator redo them before anything is written
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC1/AC2/AC3 evidence (worker, 2026-11-02):
- AC1 red: tmp/559-ac1-red.log — live probes against v2026.03.0 shape fail 'column state does not exist' and v2026.09.0 shape fails 'column rollback_finish_pending_at does not exist'.
- AC1 green: tmp/559-ac1-green.log, tmp/559-ac1-pending.log — QueryScheduledUpgrade/QueryReattemptableRestore use to_jsonb(u)->>'state' / ->>'rollback_finish_pending_at' with the pre-state-machine fallback; modern pending rows remain excluded (TestInstallDetectsPendingRollbackAsCrashedNotReattempt).
- AC3 red: tmp/559-ac3-red.log — Go refusal and install.sh fallback both still printed 'nothing was changed' with the swap flag set.
- AC3 green: tmp/559-ac3-green.log — Go says program+checkout are at the target and services/database unchanged; install.sh repeats it.
- AC2: test/install-recovery/scenarios/0-install-over-v2026-09-0-schema.sh, default LXD/fault set, LXD_BASELINE=v2026.09.0 forks installed-v2026.09.0-standalone, runs install.sh --version <candidate> over it, asserts old schema first (no rollback_finish_pending_at) then candidate binary/schema/row/health. Offline: bash -n, shellcheck (baseline warnings only), scenario-selection-test PASS, lxd-checkpoint-identity-test PASS, scenario-helper-resolution-test PASS, install-at-sha/fresh-installer/happy-install PASS.
- Full verification on combined tree: go build/vet PASS; go test ./internal/install/... ./cmd/... PASS (tmp/559-final-unit.log); STATBUS_LIVEDB_TEST_TIER=1 go test -tags livedb ./internal/install PASS (5 tests, tmp/559-final-livedb.log).
- Commits: 58e1634a1 (AC1 probes + AC2 scenario + install.sh AC3; live test state.go), 3e97a489c (giraffe AC4 commit also captured the installDetectionRefusal hunks left unstaged in the shared cli/cmd/install.go; no separate AC3 Go commit exists). Pushed to master. CI: per-commit images + LXD fault fleet must run the new scenario green; guest run still required for AC2's real proof.

CI at 1c7adbf0f: Go Test, Harness Selftest, Images, app build & lint, CodeQL, Notify cloud services all success. LXD fault fleet is tag-dispatched, not a push trigger: the next gate run must show 0-install-over-v2026-09-0-schema PASS (it is in the default scenario set).

AC4 evidence (giraffe, 2026-11-02): commits 3e97a489c (install supersedes parked in_progress attempts for other commits), c540527ee (452 historical parked-row expectation). A successful install now retires parked rows too: state='superseded', superseded_at set, original error retained with the displacement note ' — superseded by the successful install of <version>', recovery_parked_at and recovery_parked_reason cleared (required by chk_upgrade_parked_requires_in_progress; upgrade_state_log retains old_parked_at/old_recovery_parked_reason as history). Unparked attempts keep error untouched, same as before. Test452KissNormalInstallRetiresAttempts/parked: red before (tmp/559-ac4-red.log, stayed in_progress, no state-log row) and green after (tmp/559-ac4-green.log), including row evidence and the in_progress>superseded state-log assertion. Test452KissHistoricalRepairNormalInstall/parked-row updated and green (tmp/559-history-green.log). ./dev.sh test-livedb green end to end: cli/internal/upgrade 359s, cli/internal/install 367s, cli/cmd 21s, livedocker probes PASS (tmp/559-test-livedb-final.log). Install.go SQL write disposition updated in terminal_rewind_audit_test.go. On-disk marker question: ma has no tmp/upgrade-in-progress.json for row 28881 (read-only check), and a planted flag would make install Detect report StateCrashedUpgrade (flag present, flock free), which un-parks and resumes that row before success bookkeeping, so this path cannot see a live marker; no flag removal was added. Read-only ma observation: row 28881 still in_progress/parked before the fix, no flag file present. AC5 evidence (giraffe): commit 1c7adbf0f. Upgrade service now calls StampUnitFloor once after acquireAdvisoryLock (first DB-backed point in Run), before READY and the poll loop. Tests TestStartupUnitFloorStampPublishesOnceConnected and TestRunStampsUnitFloorAtStartup: red at parent 58e1634a1 in an isolated worktree (tmp/559-ac5-red.log, seam absent) and green (tmp/559-ac5-green.log). go vet (cmd, internal/upgrade, internal/install) clean, go build ./... clean, full cli/internal/upgrade unit suite green (tmp/559-test-upgrade-full.log). Read-only ma: unit_floor_state=inactive, updated_at 14:21:12 (install stamp), confirming the 6h-tick gap; fix will correct at next service boot. CI for c540527ee: Go Test, Push on master, app build & lint, Harness Selftest, Images, Notify cloud services all success; Fast Tests still in progress at 15:56Z. ACs not checked; ticket not closed.

CI for c540527ee (checked 2026-11-02T16:02Z): Go Test, Push on master, app build & lint, Harness Selftest, Images, Notify cloud services, and Fast Tests @ exercised-sha=c540527ee all conclusion=success. Fast Tests jobs: fast suite, daemon floor oracle, live-database tests, STATBUS-536 reader, STATBUS-551 worker all success.

v2026.11.1-rc.01 (3be5dc48b) gate: Smoke 41482136521, Arcs 41484453979, Hardening 41481885103, Fast Tests 41481885137, dev deploy 41484075554 all success. LXD Fork Fleet 41484330908 failed on one scenario only: 0-install-over-v2026-09-0-schema stopped at line 42 sourcing test/install-recovery/release-baseline.sh (LIB_DIR lacked /lib), before any step ran; the v2026.09.0 base itself was built fine. Reproduced locally (tmp/559/scenario-source-red.log), fixed in c7fe69c94 (LIB_DIR follows 0-happy-upgrade's convention), local run now reaches the tag check (tmp/559/scenario-source-green.log). All 26 other LXD scenarios PASS. Next: v2026.11.1-rc.02.

v2026.11.1-rc.02 (14d4ae73b) gate: Smoke 41496104420, Fast Tests 41495914064, Hardening 41495914056, dev deploy 41497484014 success. LXD Fork Fleet 41497892833: 26/27 PASS; 0-install-over-v2026-09-0-schema ERROR again before any guest step: 'no migrations found at v2026.09.0'. Cause: in the LXD shadow tree REPO_ROOT is a subdirectory of the repo, so git ls-tree <rev> migrations/ is path-relative and empty (release-baseline.sh already anchors with :(top)). Fixed in aaedbc3d4 (ls-tree -r --full-tree ':(top)migrations/'). Rehearsed in a shadow tree built exactly like run-forks.sh: fixed copy reaches bootstrap with base schema 20260901212308 and target 20261031135820 (tmp/559/shadow-rehearsal-green.log); rc.02's copy reproduces the CI error (tmp/559/shadow-rehearsal-red-rc02.log). Next: rc.03.

Manual-box findings 2026-11-02 (owner run of v2026.11.0 install.sh): (1) as root it ran on and created /root/.statbus-uninstall.lock before ./sb refused; (2) fresh install printed 'fatal: not a git repository' and 'Checked out v2026.11.0 (commit ).' because rev-parse ran before cd into the new checkout; (3) the guide gave no country answer; (4) a typo could not be corrected. Fixed (1)-(3) in 6da990385: red tmp/559/root-refusal-red.log (root run reached docker info and curl, created the lock), green tmp/559/root-refusal-green.log; red tmp/559/fresh-commit-red.log, green tmp/559/fresh-commit-green.log; tmp/559/un-green.log. (4) delegated to worker hamster (answer review before writing). Also 70bbd20ed: manual-box ssh uses C.UTF-8.

Interactive answer review (owner option A, rabbit worker 2026-11-02): commit 4790b5ed7 pushed to master. After the last question ./sb install prints 'These answers will be used for this installation:' with plain labels (Deployment mode, Domain name, Country name, Country code) and asks 'Use these answers? [Y/n]'; Enter/y accepts, n asks all questions again with the previous answers as the defaults. Nothing is written before acceptance (.env.config is still written only after the questions). installinput.Ask now takes optional previous answers; installinput.ReviewLines/AnswerValues build the summary and the fallbacks. Summary lines go through installTTYPrompt so install.sh's terminal filter shows them. Non-interactive/STATBUS_ENV_CONFIG paths unchanged. Red/green: tmp/559-review-red.log (parent tree: 'asked 4 questions, want 8 (the review must ask them all again)') and tmp/559-review-green.log (go test ./internal/installinput/... ./cmd/... all ok). Harness: setup-choices scenario expect driver answers the review and asserts the summary values, and setup-choices-driver-test.sh stand-in prints it; both PASS locally (scenario-selection-test also PASS). cli/cmd/install.go commit also carries rabbit's diskpolicy.RootRefusal hunk as requested.

CI for interactive answer review: 4790b5ed7 Go Test failed only on errcheck in the new test (unchecked answers.Close), fixed in b97f666c1. For b97f666c1: Go Test, Harness Selftest, Images, app build & lint, Notify cloud services, Push on master all success; its Fast Tests run (exercised-sha=b97f666c1) was cancelled by the newer 8fea12e54, and the change is Go-only with no SQL, so the Go Test suite covers it. Local golangci-lint (staticcheck, errcheck, ineffassign, nilness) 0 issues on ./cmd/... ./internal/installinput/....

v2026.11.1-rc.03 (068d5c93a) gate so far: Release 41531148478, Fast Tests 41531148396, Hardening 41531148543, Smoke 41531391105, dev deploy 41532826997, LXD Fork Fleet 41533051284 all success. AC2 proven: 0-install-over-v2026-09-0-schema PASS (249 s) from checkpoint installed-v2026.09.0-standalone: 'install.sh --version v2026.11.1-rc.03 completed over a real v2026.09.0 database', CA-verified HTTPS /rest/ 200. Red baseline is the ug incident on v2026.11.0 (rollback_finish_pending_at missing). Arcs pending. Next: owner runs cloud.sh install on ug, mw, ua; ma for the parked row and banner.

v2026.11.1-rc.03 gate complete, all green: Release 41531148478, Fast Tests 41531148396, Hardening 41531148543, Smoke 41531391105, dev deploy 41532826997, LXD Fork Fleet 41533051284, Upgrade Arc Harness 41533182923. Remaining: AC6 real slots (owner runs cloud.sh install ug/mw/ua/ma on rc.03).

2026-11-03 ACs checked on evidence shipped in v2026.11.1-rc.03 (gate all green, runs listed above): AC1 live old-schema probe test red/green (58e1634a1, tmp/559-ac1-*.log) plus LXD 0-install-over-v2026-09-0-schema PASS; AC3 tmp/559-ac3-red/green.log; AC4 Test452KissNormalInstallRetiresAttempts/parked red/green (3e97a489c); AC5 TestRunStampsUnitFloorAtStartup red/green (1c7adbf0f); AC7 TestInstallShRefusesRootBeforeAnyWork, fresh-installer-test commit line, TestUnitedNationsIsAnAcceptedInstallationCountry, answer-review test (4790b5ed7), all red/green. Open: AC6 (real slots). Side observation: ua upgraded itself from v2026.09.0 to v2026.11.0 through its own upgrade service (row 1861 completed 2026-11-03 10:47Z), so the old-schema defect hits ./sb install only, not the service path.

2026-11-03 cloud.sh status reported ug as v2026.11.0 (the sb program) while every container still ran d53731ec (v2026.09.0). Fixed: status adds a SERVING column read from each running container's Config.Image and flags MISMATCH (program vs serving), MIXED, NOTHING RUNNING, UNREADABLE. test/cloud-registry-test.sh red before (tmp/559/cloud-status-red.log: missing serving column), green after (tmp/559/cloud-status-green.log). Real fleet run tmp/559/cloud-status-real.log: ug 'd53731ec MISMATCH', all other slots serve their program's commit.
<!-- SECTION:NOTES:END -->
