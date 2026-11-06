---
id: STATBUS-419
title: >-
  An operator can remove a StatBus installation cleanly, from install.sh or from
  the installed system
status: In Progress
assignee: []
created_date: 2026-09-25 13:08
updated_date: '2026-11-06T16:48:00Z'
labels:
  - installer
dependencies: []
priority: high
type: feature
ordinal: 368200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
An operator who wants to start over can remove StatBus from a box with one command and then install again on the same box as if it were new.

### Zoom out
Finland needed to reinstall and had no way to remove what the installer had put down. Deleting things by hand is how the 407 credential split happens, so removal must be a product feature, not advice. It has two entry points with one behaviour: `./sb uninstall` from the installed system, and a standalone `uninstall.sh` served beside `install.sh` for a box whose installation is too broken to run `./sb`.

Removal is destructive, so the defaults protect what cannot be recreated:
- **Interactive:** backups and credentials are kept unless the operator says otherwise.
- **Unattended:** everything goes, but only with an explicit confirmation variable; without it the script refuses and says how.
- **Scope:** only the StatBus deployment (containers, volumes, images, user units, the checkout). The service account and host hardening belong to host setup and stay.
- **Safety:** it refuses while an install or upgrade holds the lock, refuses at mount and symlink boundaries rather than deleting outside the tree, and removes container-owned files without needing sudo.

### Zoom in
- **Origin, 2026-09-25:** owner request for Finland's reinstall; owner chose a separate `uninstall.sh` (13:12Z) and the interaction design (2026-09-26 08:50Z).
- **Shipped (v2026.09.3):** merge `e223af347`. `uninstall.sh` (repo root) asks `Delete database dumps too? [y/N]` and `Delete credentials too? [y/N]`; unattended needs `STATBUS_UNINSTALL_CONFIRM=yes-delete-everything`. `./sb uninstall` runs `~/statbus/uninstall.sh` (`cli/cmd/uninstall.go`). Documented in `doc/DEPLOYMENT.md`.
- **Proof, unit:** 25 `TestUninstall*` cases (`cli/cmd/uninstall_test.go`): lock held, mount and symlink boundaries, no-sudo removal of container-owned files, shared images kept, keep-choices and rerun. Green 2026-10-15.
- **Proof, real box:** `6-uninstall-reinstall.sh` removes checkout, containers and volumes without sudo, then a fresh install on the same box succeeds. PASS in rc.17 LXD `36506437069`.
- **Hosted URL:** `https://statbus.org/uninstall.sh` returns a 302 to `master/uninstall.sh` on raw.githubusercontent.com, which serves the script (checked 2026-10-15). The 2026-09-29 audit's 404 is fixed. Whether it should serve master or a release asset is STATBUS-505.
- **Gap:** before deleting, the script does not list what it is about to remove; it asks only about dumps and credentials.

### Closing review
- **Memory:** none needed.
- **Documentation:** `doc/DEPLOYMENT.md` covers it.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `./sb uninstall` and `uninstall.sh` behave the same: interactive keeps backups and credentials by default, unattended requires `STATBUS_UNINSTALL_CONFIRM=yes-delete-everything`, and both refuse safely at locks and filesystem boundaries (`TestUninstall*`, `cli/cmd/uninstall_test.go`)
- [x] #2 `curl -fsSL https://statbus.org/uninstall.sh | bash` fetches the uninstaller (302 to master's `uninstall.sh`, 200, checked 2026-10-15)
- [x] #3 On a real box, install, uninstall, and a fresh install on the same box all succeed (`6-uninstall-reinstall.sh`, rc.17 LXD PASS)
- [x] #4 `doc/DEPLOYMENT.md` documents both entry points and the hosted URL
- [x] #5 [Owner] Decide whether the uninstaller must print the list of what it will delete before asking for confirmation, and record it in Implementation Notes. No: check this and set Done. Yes: add that listing as a new criterion.
- [ ] #6 Owner decision 2026-11-02: a file StatBus creates lives in one place. While installed, users and credentials live only inside ~/statbus (.users.yml, .env.credentials); install moves a kept ~/statbus.users.yml and ~/statbus.env.credentials into the checkout (no second copy in the home). Uninstall asks 'Keep the users? [Y/n]' and 'Keep the credentials? [Y/n]'; a kept file is moved out to ~/statbus.users.yml or ~/statbus.env.credentials (mode 0600), and ~/statbus is always removed completely. uninstall.sh and ./sb uninstall behave the same; a test covers install, uninstall with both kept, and a fresh install that picks both up
- [ ] #7 uninstall.sh run after sudo -iu statbus stops the user upgrader: it supplies XDG_RUNTIME_DIR=/run/user/<uid> when unset and that directory belongs to the user (observed failing on the manual box 2026-11-02 with v2026.11.0)
- [ ] #8 Uninstall removes what the install created beside the checkout: ~/statbus-maintenance always, ~/statbus-backups (pre-upgrade backups) together with the database dumps; the plan lists both, or 'Keep: ~/statbus-backups' when the dumps are kept (observed left behind on the manual box 2026-11-03 with rc.04)
- [x] #9 Kept database dumps live outside the checkout, like users and credentials (owner decision 2026-11-05). Uninstall asks about dumps and backups only when ~/statbus/dbdumps holds a dump or ~/statbus-backups holds a backup, and names what it found; with nothing to keep it asks nothing and removes the empty folders. Kept dumps move to ~/statbus.dbdumps/ (never overwriting a different file), so ~/statbus is removed completely
- [x] #10 A fresh install moves ~/statbus.dbdumps/ back into ~/statbus/dbdumps/ and ends with a hint naming the restore command for the kept dumps; it never restores by itself. The install never deletes files it did not create: a kept ~/statbus/dbdumps left by an older uninstall is moved out first instead of being removed with a failed clone (observed: statbus_git_clone removed any ~/statbus without .git, deleting kept dumps, since v2026.09.0)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1:** green locally on master, 2026-10-15.
- **AC2:** checked with `curl` 2026-10-15. The 2026-09-29 audit had found a 404; the niue Caddyfile now redirects `/uninstall.sh` (recorded on STATBUS-505).
- **AC3:** rc.17 LXD PASS (2026-09-29 audit).
- **AC4:** `doc/DEPLOYMENT.md`, uninstall section.

### AC5 resolved 2026-10-21: already the behaviour
`uninstall.sh` prints 'StatBus removal plan (only listed resources will be deleted):' with containers, volumes, networks, image tags, unit files and paths, plus what it keeps (dbdumps, .env.credentials), then asks 'Type DELETE to execute this exact plan'. No new criterion needed. The fix is in, tested and green through the gates, so it closes under the owner's rule.

2026-11-02 manual box, v2026.11.0, sudo -iu statbus: uninstall.sh stopped at 'Step 1: stopping StatBus upgrader' with 'Failed to connect to user scope bus ... XDG_RUNTIME_DIR not defined' before deleting anything. Same cause as STATBUS-559's install failure (fixed in sb by 8fea12e54). The plan also showed 'Keep: /home/statbus/statbus/.env.credentials', leaving ~/statbus behind, while users existed twice (~/statbus.users.yml and ~/statbus/.users.yml) and were never asked about. Owner decided the one-place design above.

2026-11-02 AC6/AC7 implementation (lobster), commit 90ebd4457 (local; push held for rc.03):
- Install (cli/cmd/install_users.go, one call before the step table in install.go): adoptOperatorUserState moves ~/statbus.users.yml and ~/statbus.env.credentials into the checkout (rename, 0600), before Credentials/Administrator read them. Identical duplicate at the destination is removed (one copy); different contents refuse, naming both paths. STATBUS_USERS_FILE is copy-only and never moved. persistInteractiveAdministrator now writes only <checkout>/.users.yml.
- Credentials reuse: because the move happens before the Credentials step, checkCredsDone is satisfied and config.GenerateInDir keeps the existing secrets. This is what keeps a surviving DB volume consistent; cli/internal/dbroles is the backstop when the volume outlives the credentials.
- Uninstall (uninstall.sh, used by ./sb uninstall): asks 'Keep the users? [Y/n]' and 'Keep the credentials? [Y/n]' (keep by default); unattended keeps neither. Kept files move to ~/statbus.users.yml / ~/statbus.env.credentials at 0600, refusing a different existing file before anything is stopped. The plan lists 'Move to ...'. .env.credentials is no longer excluded from deletion, so the checkout is removed completely (a kept dbdumps/ still keeps the empty directory, see doubt below).
- AC7: uninstall.sh exports XDG_RUNTIME_DIR=${STATBUS_USER_RUNTIME_DIR_BASE:-/run/user}/<uid> when unset and the directory belongs to the user, before any systemctl --user call (same rule as cli/cmd/user_runtime_dir.go).
- Tests red then green (tmp/419-red.log, tmp/419-go-cmd.log, tmp/419-go-all.log): 5 new adopt tests, updated interactive-admin single-copy test, 4 uninstall.sh tests (interactive keep on a PTY, overwrite refusal, unattended removes, XDG supplied to systemctl), terminal-filter move line. gofmt/vet/build clean; go test ./cmd/... PASS; harness scenario-selection and release-script-stamp selftests PASS.
- Scenario 6 now: install -> one copy only inside checkout -> login -> interactive uninstall (Enter, Enter, Y, DELETE) -> ~/statbus gone, both home files 0600 -> reinstall -> home files gone, credentials sha unchanged, login succeeds again.
- Doubt for rabbit/owner: with dbdumps kept by default, the checkout directory still remains ('Only selected backups remain'), contradicting '~/statbus is always removed completely'. Proposed follow-up (not implemented, needs OK): move kept dumps to ~/statbus-dbdumps so the checkout always goes.
- Note: go test ./... in cli fails only in TestNoGoPackageDirectoryIsGitignored_STATBUS352 because of the shared-checkout scratch dir cli/tmp/verify557/ (another worker, untracked); ./cmd/... is green.

Replayed after rc.03: code commit dfe262b0b (was 90ebd4457), ticket evidence a9f2eba96 (was 3703c3fd7), both on origin/master. CI for tip aaedebceb1b6c620b757a7864826ce62f20a712a (includes both): Go Test success, Harness Selftest success, app build & lint success, Images success, CodeQL success, Notify cloud services success (gh run list, 2026-11-02T21:52Z). Push hold released.

CI for 3df6bdc36d7b462eaf8ab533910ace895c085d20 (final ticket-evidence commit): Fast Tests success, Harness Selftest success, Images success, CodeQL success, Notify cloud services success (2026-11-02T22:10Z). Code commit dfe262b0b was covered green by the aaedebceb tip run (Go Test, app build & lint, Harness Selftest, Images, CodeQL, Notify).

v2026.11.1-rc.04 (6de3d2757) gate all green: Orchestrator 41694665449, Release 41694665586, Fast Tests 41694665437, Hardening 41694665619, Smoke 41694992526, dev deploy 41697559548, LXD Fork Fleet 41698073420, Upgrade Arc Harness 41698438796. First release containing AC6/AC7 (dfe262b0b); real-box check is the owner's manual-box walkthrough on rc.04.

- **AC8 (2026-11-03):** `46aae5c38`. `TestUninstallRemovesTheInstallsHomeFolders` red before the fix (`tmp/uninstall-home-folders-red.log` in statbus_test: both folders kept, plan lines missing), green after; full `TestUninstall*` green. Box observation pending with rc.05.

- **2026-11-04 `f9d7f2d8f`:** ~/.statbus-uninstall.lock was left in the home after a full removal (seen on the manual box). uninstall.sh now unlinks it as its last operation while still holding the flock. TestUninstallLeavesNoLockFileBehind red (tmp/uninstall-lock-red.log: home held .statbus-uninstall.lock), green; TestUninstall* green.

AC9/AC10 (2026-11-06), test first:
- Clone (AC10): test/install/install-keeps-kept-backups-test.sh through a new STATBUS_INSTALL_TEST_GIT_CLONE seam running the real statbus_git_clone. Red (tmp/install-keeps-kept-backups-red.log in statbus_test): kept dump deleted, a foreign file in ~/statbus deleted, the clash case deleted both. Fix: statbus_clone_destination_prepare sets old-layout ~/statbus/dbdumps aside in ~/statbus.dbdumps (never overwriting), refuses any other file with its name; the clone wrapper no longer deletes (real git removes its own failed clone: tmp/real-git-failed-clone-leftovers.log). Green: tmp/install-keeps-kept-backups-green.log.
- Install (AC10): adoptKeptBackups moves ~/statbus.dbdumps into <checkout>/dbdumps before the steps; reportKeptBackups ends the install with the newest backup and 'cd ~/statbus && ./sb db restore <file>'; never restores. Terminal filter passes the lines. Tests TestAdoptKeptBackups*, TestKeptBackupsLinesReachTheTerminal: red (undefined / lines hidden, tmp/install-kept-backups-go-red.log, tmp/kept-backups-terminal-red.log), green after.
- Uninstall (AC9): asks 'Keep the N database backup(s)? [Y/n]' only when dbdumps holds a .pg_dump; kept files move to ~/statbus.dbdumps (refusal before teardown if a different file has the same name); ~/statbus removed completely; ~/statbus-backups (upgrade snapshots) always removed; the plan and the answers are written to ~/statbus-uninstall.log. Tests TestUninstallKeepsBackupsOutsideTheCheckout, TestUninstallAsksAboutBackupsOnlyWhenThereAreSome, TestUninstallRefusesToOverwriteADifferentKeptBackup; red against the old script (it asked a different question and waited for an answer; the test hung), green with all 34 TestUninstall* (tmp/uninstall-kept-backups-green.log). piped-scripts-test and 6-uninstall-reinstall follow the new question. DEPLOYMENT.md updated.
- Box proof follows on rc.13.

AC8 is refined by the owner decision of 2026-11-05 (backup = daily pg_dump, upgrade snapshot = ~/statbus-backups): the upgrade snapshots are always removed, never kept with the backups, so the plan no longer prints 'Keep: ~/statbus-backups'. TestUninstallRemovesTheInstallsHomeFolders now asserts that in both cases.

rc.15 gate GREEN 2026-11-06 (v2026.11.1-rc.15 at 91d060e64; Orchestrator 42246017808: Smoke 42246222921, Hardening, Fast Tests, Deploy to dev 42248010572, LXD Fork Fleet 42248246593, Upgrade Arc Harness 42248399837). 6-uninstall-reinstall PASS in the LXD fleet with the kept-backup flow.
<!-- SECTION:NOTES:END -->
