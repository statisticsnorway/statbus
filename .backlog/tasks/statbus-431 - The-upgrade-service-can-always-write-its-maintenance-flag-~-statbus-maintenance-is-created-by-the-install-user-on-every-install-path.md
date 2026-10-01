---
id: STATBUS-431
title: >-
  The upgrade service can always write its maintenance flag:
  ~/statbus-maintenance is created by the install user on every install path
status: In Progress
assignee: []
created_date: '2026-09-29 10:28'
updated_date: '2026-10-01 11:40'
labels:
  - install
dependencies: []
priority: high
ordinal: 380200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Issue (observed live, 2026-10-01).** The v2026.10.0-rc.01 smoke gate's 0-happy-upgrade scenario (run 36851924215) installed a v2026.09.3 base, scheduled the upgrade to the candidate, and the upgrade daemon failed 5 seconds in:

```
could not enter maintenance mode before stopping services:
write maintenance flag /home/statbus/statbus-maintenance/active: permission denied
```

**Root cause, step by step.** The only code that creates `~/statbus-maintenance` and `~/statbus-backups` lives inside `runGenerateEnv` (install.go:1597-1603), the "Settings" step. The Settings step's done-check is `checkEnvDone` = `GeneratedFilesMatch`. Since 2026-09-24/25 (`8d8f48704` made reruns quiet via `GeneratedFilesMatch`; `626bc0d9b` made the Credentials step generate `.env` itself), the Settings step is skipped on **every** fresh install: Credentials has just generated `.env`, so "generated files match" is already true. The failing guest's own install trace proves the sequence:

```
[4/17] Configuration   OK              ← skipped (.env.config pre-seeded by the harness)
[5/17] Credentials     RUNNING→DONE    ← generates .env
[6/17] Settings        OK              ← skipped; directory creation never runs
[8/17] Services        RUNNING→DONE    ← compose up: Docker creates the missing
                                          ~/statbus-maintenance as ROOT
                                          (caddy/docker-compose.yml:28 bind mount)
```

At upgrade time the daemon (user statbus) defensively `os.MkdirAll`s the directory (upgrade/exec.go:462-465) — which is a no-op when it already exists root-owned — and the flag write fails. This failure mode is unrecoverable by the daemon as shipped.

**Scope correction (supersedes the 2026-09-29 note below).** This is not limited to pre-seeded `.env.config` paths: since 2026-09-24/25 **every install path** (interactive, answer file, pre-seeded, rerun) skips Settings and leaves directory creation to Docker-as-root. NSO live boxes (dev/no/demo, verified 2026-09-29: statbus-owned, 755/775) predate the regression and are unaffected. Any box installed by a v2026.09.x installer is affected; its first upgrade fails at maintenance entry.

**Root cause class (owner-approved framing, 2026-10-01).** Step done-checks test *proxy artifacts* (a file exists; generated files match) while steps carry *unrelated side effects* (directory creation). Whichever step satisfies the proxy first silently deletes the side effects. Additionally, mkdir failures in `runGenerateEnv` are swallowed with `log.Printf` instead of failing the step.

**Principled fix (owner-approved strategy, 2026-10-01).**
1. **New early "Directories" step** in the install step table, before Services: creates `~/statbus-maintenance` and `~/statbus-backups` as the install user. Its done-check is outcome-based: directory exists AND is owned by AND writable by the install user. mkdir errors are fatal, never logged-and-continued.
2. **Configuration done-check becomes "valid and complete `.env.config`"** rather than "exists". Pre-seeded `.env.config` remains a legal provisioning input (ops/cloud genuinely inject slot facts the product cannot know; config generation is first-writer-wins from the file).
3. **Daemon self-repair:** before writing the maintenance flag, if the directory exists but is not writable by the service user, repair ownership via the shared container mechanism (the STATBUS-429 `cert install` pattern: box's proxy image, alpine fallback, no network), then proceed. This is the only way to heal boxes installed by the released v2026.09.x installers, which a fixed installer can never re-run on.
4. **Harness cleanup:** keep the lxd-backend mkdir guards until the gate proves green, then remove the workaround blocks and convert the ownership regression test to assert the product invariant via a guest run.
5. Re-cut as v2026.10.0-rc.02; rc.01 is superseded by design.

**Explicitly out of scope (separate design ticket).** Whether `.env.config`/`.env.credentials` should move out of the product-owned checkout (`~/statbus/`) to an operator-owned location (`~/statbus-config/`). Upgrade uses `git checkout -f` (no `git clean`), so settings survive swaps today, but wholesale-checkout deletion paths (slot reset, STATBUS-426's adopt scenario) destroy them. Owner question 2026-10-01; filed separately so rc.02 stays scoped.

Found by review tmp/review-425-m3a.md R3 (2026-09-29), first hit live on LXD arcs (un-park-to-completion could not write its park flag). cli/cmd/install.go runCreateConfig (install.go:1504, the Configuration step) is the only place that creates $HOME/statbus-maintenance (install.go:1601-1605), and it runs only when .env.config is absent (checkConfigDone, install.go:1172). Any install where .env.config already exists skips it: the unattended answer file (STATBUS_ENV_CONFIG imports .env.config), ops/create-new-statbus-installation.sh (touch .env.config, line 346), and a rerun after an interrupted install. Then caddy/docker-compose.yml:28 bind-mounts ${HOME}/statbus-maintenance and Docker creates it as root, so the upgrade daemon (running as statbus) cannot write the maintenance/park flag (cli/internal/upgrade/exec.go:428-439). Fix: create the directory (and statbus-backups) owned by the install user on every install path, before any container starts, and repair a root-owned one on existing boxes (same container mechanism as Backup ownership / STATBUS-429).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every install path (interactive, answer file, pre-seeded .env.config, rerun) leaves ~/statbus-maintenance and ~/statbus-backups owned by and writable by the install user before the first compose up, verified by guest runs on each path
- [ ] #2 (a) A fleet-faithful v2026.09.3 base (directories statbus-owned, as every production box is) upgrades to the fixed candidate and completes — the smoke gate. (b) A post-regression box (root-owned ~/statbus-maintenance) is healed by `./sb install` of the candidate, which repairs ownership via the shared container mechanism without sudo, and the pending upgrade then proceeds to completion. rc.02 (run 36877708943) proved the daemon cannot self-rescue on a 09.3 base: the maintenance write runs in the OLD binary's pre-swap phase (PhaseOldSbUpgrading), before the new binary exists
- [ ] #3 Directory creation and repair failures fail their step loudly; no log.Printf swallow
- [ ] #4 Directory creation no longer rides on the Settings or Configuration steps' done-checks; those checks verify their own outcomes only
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Scope correction 2026-09-29 (coordinator): an answer-file install DOES create the directory: runCreateConfig reads STATBUS_ENV_CONFIG (install.go:1507) and the Configuration step runs because .env.config is absent. Only paths that pre-create .env.config before install skip it: the test harness (vm-bootstrap.sh copies /tmp/env-config to ~/statbus/.env.config) and ops/create-new-statbus-installation.sh (touch .env.config, line 346). Live boxes checked: dev statbus_dev 775, no statbus 755, demo statbus_demo 775, all owned by the service user. So no NSO box is affected today; the fix is still right (create the directories on every path, not only inside Configuration).

Correction of the correction, 2026-10-01: the note above is superseded by the Description's live evidence. `runCreateConfig` has no mkdirs at all at 4eba1149e; the only creation site is `runGenerateEnv` (Settings step), and since `8d8f48704`/`626bc0d9b` (2026-09-24/25) the Settings step is skipped on every fresh install because Credentials already generated `.env`. Verified against the failing guest's step trace in smoke run 36851924215 (`tmp/rc01-smoke-0happy-upgrade.log`).

2026-10-01 11:40 UTC: owner approved the principled fix (Description) and raised this to the rc.02 blocker. Owner decision recorded in the session: pre-seeded `.env.config` stays a supported provisioning input; the `.env.config` location question (operator-owned directory outside the checkout) is a separate design ticket, not rc.02 scope. rc.01 remains published; rc.02 will supersede it.
<!-- SECTION:NOTES:END -->
