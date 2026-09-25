---
id: STATBUS-417
title: Every fault scenario starts from one installed snapshot on a warm LXD box in seconds, while happy install and happy upgrade keep proving fresh VMs
status: To Do
assignee: []
created_date: '2026-09-25 11:15'
updated_date: '2026-09-25 17:42'
labels:
  - harness
  - velocity
dependencies: []
priority: high
type: enhancement
ordinal: 368000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every fault scenario currently re-pays the same approximately ten-minute provisioning, hardening and install prefix. The [rc.02 install-recovery run 36104217764](https://github.com/statisticsnorway/statbus/actions/runs/36104217764) has 23 scenarios, each provisioning, hardening and installing its own CX23, subject to Hetzner's one-hour minimum VM billing. A serial full gate takes over an hour and cannot start until the previous fleet finishes. Instead, use one warm, dedicated throwaway box with a Btrfs LXD pool. For each candidate, run the real hardening and `install.sh` once inside a base guest using that candidate's own tagged assets, establish health, stop it and `lxc snapshot base installed`. Each fault scenario starts with `lxc copy base/installed <name>`, starts that fork, and runs its original injection and **unchanged assertions**. Reset by deleting and recopying. Happy install and happy upgrade remain on fresh Hetzner VMs for each Ubuntu version as the proof of record, not forks of an already installed system. The owner chose dedicated Btrfs, not rune: rune is possible but not optimal and is not used.

### Grounded prototype evidence, 2026-09-25

- `tmp/throwaway-lxd-prototype.md`, P1/P2/P4: on the dedicated Hetzner Btrfs host, actual rc.03 hardening took 55.07 + 3.02 = **58.09 s** after correcting a backup-file verifier and `/run/sshd`; actual `install.sh` took 137.05 + 21.15 = **158.20 s**, the first invocation failing because its non-login shell lacked `XDG_RUNTIME_DIR`. After a 2.94 s base stop, snapshot took **0.32 s**, three CoW fork copies **0.31 / 0.28 / 0.30 s**, and their starts reached `/rest/` HTTP 200 in **11 / 11 / 10 s**. Three installed forks ran concurrently. Deleting a fork and recopying took **1.66 + 0.27 = 1.93 s**, plus 10 s to readiness. These are measured operations, not a measured fleet wall time.
- That prototype's P3 **did not pass the orphaned-volume fault**: the regenerated credentials differed from the surviving volume; reinstall failed step 8 Services in 15 s with `the API service (rest) is still missing published host port 3013/tcp after recreation`, while PostgREST logged `password authentication failed for user "authenticator"`. A second installer attempt failed preflight rc=78, `No valid release signer is configured`. In rc.03 `cli/cmd/install_services.go`, `reconcilePublishedPorts(dir)` at line 510 precedes `syncRolePasswords(dir)` at line 521; the rest restart prevents reconciliation reaching password sync. The scenario's 60 s stability assertion was **not attempted**, and no manual role sync was used. Fix the actual ordering bug in a new candidate rather than weakening the assertion. Also retain fixtures outside guest `/tmp` (tmpfs), remove root-owned Caddy bind mounts as root, invoke install from a login shell and keep test-only guest port binding off public interfaces.
- `tmp/rune-lxd-prototype.md`, second P3/P5: rune's XFS filesystem can reflink a raw `cp`, but LXD's `dir` driver actually copied its installed ~5 GB tree: snapshot **36.54 s**, forks **39.89 / 38.51 s**, approximately 4.9–5.0 GB physical per fork. Two forks reached HTTP 200 in 12/13 s once bridge-scoped firewall rules permitted DHCP. The prototype deleted its instances, pool, bridge and temporary files and restored UFW rules; **LXD snap remained installed** according to P5. Rune is not selected as the fleet box.

### Integration boundaries and decisions still open

- **Owner's filesystem boundary:** rune remains a representative production box with a plain XFS installation, exactly as an operator would install StatBus, so its real-life performance stays measurable. Btrfs is **not** suitable for production PostgreSQL: PostgreSQL already keeps its own write-ahead log, and a copy-on-write filesystem journals again, doing double work. This cost is irrelevant for disposable test forks, where Btrfs's near-instant snapshots and copies are exactly what we need. Therefore the fault fleet runs on a dedicated throwaway box with a Btrfs LXD pool, **never on rune**.
- Add the LXD backend to STATBUS-359's dispatcher as its second backend. STATBUS-416 candidate supersession must be checked per fork before allocation/start, with an observable neutral SUPERSEDED fleet verdict rather than a false failure or green result. Keep the current assertions independent of backend and do not substitute a handcrafted checkout or image for the candidate's own installer/assets.
- Decide whether the dedicated box persists warm between candidates or is created per candidate, and whether GitHub Actions uses a self-hosted runner there or SSH to it. Capture isolation, credentials, cleanup, capacity and cost in the implementation. Neither prototype measures the whole 23-scenario gate, so its under-15-minute target is a target, not an observed result.
- Inspect scenario headers and explicitly route host-specific cases before moving them: `0-https-only-egress.sh` exercises hardened CrowdSec nftables/UFW and may require an LXD VM; `4-install-40gb-disk.sh` requires the real 40 GB disk policy and should remain a fresh VM or an accurately sized LXD VM; `4-install-port-80-taken.sh` needs a genuine port owner and public certificate path; `4-install-standalone-no-public-dns.sh` tests DNS/certificate behavior. Boot/systemd cases (`1-boot-*.sh`, `5-install-stage-c-systemd-failed.sh`) require guest systemd fidelity, and the remaining `5-install-*` fault scripts and `3-postswap-worker-ddl-deadlock.sh` need Docker, PostgreSQL and upgrade-service behavior. Determine, rather than assume, which require a kernel, reboot, firewall or boot boundary unavailable to containers; run those on LXD **VMs on the same box** if needed, retaining their assertions. Happy install and upgrade do not migrate to the fork backend.
## Stage 1 by hand, 2026-09-25 (rc.05)

Backend prototype: branch `harness/lxd-backend-stage1` (commits `c117223c9`, `afa570eda`, `73ddaa181`, not merged). Evidence: `tmp/lxd-stage1.md` (22 scenarios, per-run wall time, rc, logs). One base built with the real `install.sh` for `v2026.09.3-rc.05`, `/rest/` 200; Btrfs copy under 1 s; fork boot to 200 in 8-11 s.

- 8 scenarios reached their unchanged PASS marker on forks: 5-install-proxy-never-started 29 s, 5-install-bool-text-regression 31 s, stages A-E 28-99 s, 1-boot-startup-timeout 193 s (real systemd NRestarts 0->1). Stage A and B pass markers have injection caveats (Phase 1 PID absent; pool saturation may not have engaged).
- 14 scenarios were red for precondition reasons, not rc.05 product failures: the backend built ONE base in `private` mode, but scenarios declare their own starting point and mode.

Defect in the stage-1 specification (coordinator error, not the worker's): the scenario scripts already declare their mode and starting state (`HARNESS_DEPLOYMENT_MODE` per script; standalone in 4-install-port-80-taken, 5-install-orphaned-db-volume-credentials, 4-install-standalone-no-public-dns; private in 0-happy-install, 4-install-40gb-disk, 5-install-interrupted-restart, 5-install-live-upgrade-wait, 0-interactive-admin-password; development in 0-happy-upgrade and the vm-bootstrap default), and several start FRESH or from a previous stable baseline. The backend must fork from the checkpoint each scenario's own script requires: (a) hardened, nothing installed (scenario runs install.sh itself); (b) installed-<candidate>-<mode>; (c) installed-<previous stable>-<mode> for upgrade/concurrency scenarios; plus a per-instance root quota for 4-install-40gb-disk and APT index present for interactive scenarios.

Open before stage 2: the deployment-mode question in the new ticket on NSO-representative harness modes (which mode the proofs of record must use).

## Owner lifecycle decision, 2026-09-25 17:41Z

The warm box is not permanent: **ramp up on demand, keep it around roughly 24 hours after last use, then clean up.** The automation (stage 3) must implement: an idle-timeout reaper (delete the box when unused > ~24 h) and a fast ramp-up path (recreate + harden + build the candidate base unattended; consider a Hetzner snapshot of the hardened LXD host to make ramp-up minutes instead of a full harden cycle).

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A `test/install-recovery/lib/lxd-*.sh` backend accepts a candidate tag, hardens and runs the real candidate `install.sh` and assets once, verifies the installed base, snapshots it, and logs timed snapshot, copy, boot/readiness and cleanup phases with candidate identity.
- [ ] #2 `5-install-orphaned-db-volume-credentials.sh` passes on a fork with identical assertions, including stability, or this ticket records the actual reproducible product bug and its failing candidate/run rather than claiming green; fix and rerun the rc.03 ordering defect before a green gate.
- [ ] #3 The fleet workflow dispatches its eligible fault subset to the warm box through STATBUS-359, routes incompatible cases to LXD VMs or explicitly retained fresh VMs, and the smoke workflow still proves happy install and happy upgrade on fresh Hetzner VMs per Ubuntu version. Record the selected scenario inventory and unchanged assertion results.
- [ ] #4 Record actual fault-subset gate wall time, run ID, scenario counts, concurrency, box setup amortization and billing in this ticket. Target **under 15 minutes**, measured from dispatch to aggregate verdict, rather than extrapolating prototype fork timing.
- [ ] #5 Exercise STATBUS-416 supersession during a fork fleet: a newer candidate prevents the next fork from starting, active forks clean up safely, the old aggregate reports SUPERSEDED and the new candidate can proceed. Record the run IDs and observable verdicts.
<!-- AC:END -->
