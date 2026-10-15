---
id: STATBUS-419
title: >-
  An operator can remove a StatBus installation cleanly, from install.sh or from
  the installed system
status: In Progress
assignee: []
created_date: '2026-09-25 13:08'
updated_date: '2026-10-15 19:21'
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
- [ ] #5 Owner decision: should the uninstaller print the list of what it will delete before asking for confirmation (the original criterion), or are the two keep-questions enough? Yes adds that as the open criterion; no closes this ticket.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1:** green locally on master, 2026-10-15.
- **AC2:** checked with `curl` 2026-10-15. The 2026-09-29 audit had found a 404; the niue Caddyfile now redirects `/uninstall.sh` (recorded on STATBUS-505).
- **AC3:** rc.17 LXD PASS (2026-09-29 audit).
- **AC4:** `doc/DEPLOYMENT.md`, uninstall section.
<!-- SECTION:NOTES:END -->
