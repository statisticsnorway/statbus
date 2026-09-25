---
id: STATBUS-419
title: An operator can remove a StatBus installation cleanly, from install.sh or from the installed system
status: To Do
assignee: []
created_date: '2026-09-25 13:08'
updated_date: '2026-09-25 13:13'
labels:
  - installer
priority: high
type: feature
ordinal: 368200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finland wants to do another installation and needs a clean removal path first (owner, 2026-09-25). Today there is no uninstaller: nothing removes what `install.sh` and `ops/setup-ubuntu-lts.sh` put down. The owner wants removal triggerable **from the installer directly** and **from the local installation** (`./sb uninstall`). Owner decision 13:12Z: a **separate `uninstall.sh`** script (served like `install.sh`, e.g. `curl -fsSL https://statbus.org/uninstall.sh | bash`), not flags inside install.sh.

## What an installation puts down (grounded 2026-09-25)

- Docker: containers `statbus-<code>-{db,rest,app,proxy,worker}`, named volumes (database data, caddy data incl. certificates), networks, pulled images (`sha-<commit>` tags).
- Files: the `~/statbus` checkout incl. `.env`, `.env.config`, `.env.credentials`, `caddy/data/custom-certs/` (operator-provided private keys), `dbdumps/` (backups), logs, `tmp/`.
- Systemd: user units (`ops/statbus-upgrade.service`, restart units) and enabled linger for the service account.
- Accounts/host: the `statbus` service account (`ops/setup-ubuntu-lts.sh:1192`), host hardening (firewall, apt timers) from step 1 of DEPLOYMENT.md.

## Open design questions (owner)

- Default preservation: keep `dbdumps/` and `.env.credentials` unless a flag says delete? Or delete everything with a typed confirmation?
- Does removal include the `statbus` user and host hardening, or only the StatBus deployment (user/hardening belong to host provisioning, step 1)?
- Naming: `./sb uninstall` locally and a standalone `uninstall.sh` served at statbus.org (owner decision: separate script, 2026-09-25 13:12Z).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `./sb uninstall` on an installed system removes containers, volumes, images, units and the checkout, printing exactly what will be deleted and requiring explicit confirmation first.
- [ ] #2 The same removal is triggerable via a standalone `uninstall.sh` served at statbus.org, with identical behavior and output conventions (plain operator text, step lines visible).
- [ ] #3 An install-recovery scenario proves: install, uninstall, fresh install succeeds on the same box.
- [ ] #4 Documentation in doc/DEPLOYMENT.md.
<!-- AC:END -->
