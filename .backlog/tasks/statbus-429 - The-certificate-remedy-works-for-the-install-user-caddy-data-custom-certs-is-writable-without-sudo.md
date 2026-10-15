---
id: STATBUS-429
title: >-
  An operator installs a certificate with ./sb cert install as the install user,
  without sudo
status: In Progress
assignee: []
created_date: '2026-09-29 08:24'
updated_date: '2026-10-15 19:26'
labels:
  - install
dependencies: []
priority: high
ordinal: 378200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
An operator can put a certificate on a StatBus box as the install user with the one command the product prints, `./sb cert install`, and never needs sudo or a manual copy.

### Zoom out
Once the web entry point has started, Docker owns `caddy/data/` as root because it bind-mounts it. The certificate remedy the installer printed told the operator to place files under `caddy/data/custom-certs/`, which the install user then could not do. A remedy that cannot be followed as written is worse than none.

Owner direction (2026-09-29): operators fix certificates only with `./sb cert install`, never by copying files. So the product must make that command work on every box:
- **Repair:** it makes `caddy/data/custom-certs/` writable itself, through a container, without sudo.
- **One remedy:** every certificate refusal names `./sb cert install` with full paths.

A second, later step: let the installer accept the certificate up front, through the same code path, so a fresh install is born serving it. The private-certificate choice is STATBUS-399, a separate ticket.

### Zoom in
- **Incident, Finland replay, 2026-09-29:** LXD forks of Ville's exact broken v2026.09.2 state (`tmp/ville-replay-v2026.09.3.md` D3, `tmp/ville-cert-install-replay.md`). `caddy/data/` was `root:root 755`; `./sb cert install` failed with `mkdir custom-certs: permission denied` (`cert.go writeCertAndKey`) on both v2026.09.2 and v2026.09.3, with no guidance. After a one-time ownership fix it worked end to end.
- **Shipped (v2026.10.0):** merge `8579e6e61` (+ `a0ee1f2ed`). `./sb cert install` repairs an unwritable `custom-certs` through a container (the box's proxy image, alpine fallback, no network) via the shared `cli/internal/hostrepair`, also used by STATBUS-431. Every certificate remedy now names `./sb cert install <full path to certificate> <full path to key>` (`ad7876f0b`, `828b04984`); `doc/DEPLOYMENT.md` renewal uses full paths (`7bd5fd612`).
- **Proof, unit:** `TestEnsureCustomCertsDirWritable_ExistingUnwritableDirIsRepaired`, `..._DockerRepairFailureIsPlainRemedy`, `..._RepairExitsZeroButStillUnwritable` (`cli/cmd/cert_test.go`), `TestEnsureWritable*` (`cli/internal/hostrepair`). Green 2026-10-15.
- **Not yet run:** `test/install-recovery/scenarios/5-install-cert-repair-via-cert-install.sh` is written and reviewed but carries `HARNESS_SKIP_DEFAULT` and its own header says it has never run on the LXD fleet.
- **Not built:** installer certificate arguments. `install.sh` and `./sb install` take no certificate inputs today; only `./sb cert install` calls `loadCertMaterial`.

### Closing review
- **Memory:** none needed.
- **Documentation:** `doc/DEPLOYMENT.md` covers `./sb cert install`; installer arguments need a line there when built.
- **Cleanup:** remove `HARNESS_SKIP_DEFAULT` from the scenario after its first green run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `./sb cert install` succeeds as the install user when `caddy/data` is root-owned, repairing only `custom-certs` through a container without sudo, and fails with a plain remedy when it cannot (`TestEnsureCustomCertsDirWritable_*`, `TestEnsureWritable*`)
- [x] #2 Every certificate refusal names `./sb cert install` with full paths (`ad7876f0b`, `828b04984`; install.sh `INSTALL_FIX` allowlist)
- [ ] #3 An explicit LXD run of `5-install-cert-repair-via-cert-install.sh` on a built candidate: a box that has run Services follows the printed remedy as the install user and reaches a ready installation with CA-verified HTTPS
- [ ] #4 The installer accepts a certificate and key pair, or one PFX/PKCS#12 file with its password from an environment variable, through the same code path as `./sb cert install`, refuses them in private and development modes, and a fresh install is born serving that certificate
- [ ] #5 Owner decision: is AC4 (installer certificate arguments) still wanted now that `./sb cert install` works, or does it move to STATBUS-399, which redesigns the certificate choice? Moving it lets this ticket close on AC1-3.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** green locally on master, 2026-10-15; shipped in v2026.10.0.
- **AC3:** open; scenario never run (its header, 2026-10-15).
- **AC4:** open; no installer certificate inputs on master `cb34436b4`.
- **History:** the 2026-09-29 replay notes, merge notes and 2026-10-01 reconciliation are folded into Zoom in; full text in Git history.
<!-- SECTION:NOTES:END -->
