---
id: STATBUS-419
title: >-
  An operator can remove a StatBus installation cleanly, from install.sh or from
  the installed system
status: In Progress
assignee: []
created_date: 2026-09-25 13:08
updated_date: '2026-11-02T21:52:00Z'
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
<!-- SECTION:NOTES:END -->
