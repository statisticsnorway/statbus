---
id: STATBUS-376
title: >-
  A third-party operator installs StatBus on Ubuntu 26.04 from the instructions
  alone (Finland NSO)
status: To Do
assignee: []
created_date: '2026-09-18 17:48'
updated_date: '2026-09-24 14:53'
labels:
  - install
  - setup
  - ubuntu
  - third-party
  - release
  - fail-fast
dependencies: []
references:
  - STATBUS-369
priority: high
type: bug
ordinal: 1
---

## Third-party transcript (Finland NSO, 2026-09-18)

Ville-Mattis Pilvio tested the StatBus install in the Finland NSO sandbox on
Ubuntu 26.04 LTS. As `statbus`, he ran `setup-ubuntu-lts.sh`, then:

    curl -fsSL https://statbus.org/install.sh | bash -s -- --channel prerelease

At Stage 6, `GITHUB_USERS=villemattipilvio` returned no keys. The setup emitted
a warning, then logged `0 key(s) written` as `[OK]`. It created `devops` with
passwordless sudo and no authorized key, locking the operator out, and the
verification failed. The default deploy-key source,
`https://github.com/statisticsnorway/statbus.keys`, returns 404, so that default
can never work.

He manually added `authorized_keys`. He also had to run
`sudo apt install ssh`: the image lacked `openssh-server`, while Stage 2 tried to
harden `sshd` without installing the server. Stage 7 passed after he added a key
to GitHub. Stage 8 was skipped with `[WARN]` and a hint naming the fleet-only
`SSHDOERS_REF`. The final setup summary nevertheless claimed unconditionally
that the CI command allowlist was installed.

Under the curl pipe, `install.sh` inherited non-TTY stdin. `sb install` therefore
went non-interactive and demanded `STATBUS_ENV_CONFIG`. The transcript also
contained Git noise (`is not a commit!`, detached-head advice, and `branch
'current' tracks a tag`), a `SYSTEM UNUSABLE` banner for a pre-flight refusal,
and an unexplained `TRUST_GITHUB_USER` prompt.

## Defects and current state

1. **D1:** The deploy-key default always returns 404.
2. **D2:** Zero fetched keys are reported as `[OK]`; `devops` is created with
   passwordless sudo but no authorized key; there is no preflight proving that
   configured users have keys before `useradd`.
3. **D3:** Setup hardens `sshd` but never installs `openssh-server`.
4. **D4:** `VERSION_ID != 24.04` is warning-only.
5. **D5:** The GitHub-user prompt does not explain why GitHub identity is being
   requested or what it configures.
6. **D6:** Stage 8 skip is warning-level and its hint exposes fleet-only
   `SSHDOERS_REF` to public installers.
7. **D7:** The summary prints static claims rather than observed stage results;
   the current static summary is at `setup-ubuntu-lts.sh:1690`.
8. **D8-D11 are fixed in `9e57c1722`:** curl-pipe stdin handling; tag checkout
   noise and the `current` branch; `SYSTEM UNUSABLE` for pre-flight refusals;
   and the `TRUST_GITHUB_USER` explanation.

Two stale references remain in scope: `doc/releases.md:152` still names
`devops@<host>`, and `ops/statbus-upgrade.service:82` still carries the Linuxbrew
`PATH`.

## Binding owner decisions (2026-09-18)

1. **Split public setup from SSB fleet setup.** The public hardening script stays
   essentially a hardening + Docker + `statbus` service-account installer. An
   SSB cloud script layered on top owns `devops`, GitHub key fetching,
   `SSHDOERS_REF`, and other fleet-only behavior. Public setup must contain no
   fleet concepts, require zero GitHub credentials, use HTTPS only, finish
   warning-free, and build its summary solely from stage results.
2. **Service-account key input supports both forms:** direct paste and file/env.
3. **Ubuntu 26.04 LTS is the primary harness image.** Retain exactly one
   24.04 happy-upgrade path: previous release to candidate on the fleet's
   Ubuntu 24.04. Readiness is established by running the harness, not by analysis.
4. **The harness installs by VERSION, normally an rc tag, exactly as operators
   do.** Commit pinning remains only as an optional debugging override.

## Implementation inventory

Use `tmp/setup-simplification.md` as the stage-by-stage inventory and its
PUBLIC/FLEET/DROP classification. Its rename-impact list includes:

- `vm-bootstrap.sh:720`
- `test-hardening.yaml:27,47-48`
- `ops/release/upgrade-sensitive-paths.txt:49`
- `release_sshdoers_drift.go:20,173`
- `sensitive_paths_list_test.go:39`
- `DEPLOYMENT.md:136,159`
- `CLOUD.md:745,768,774`
- `setup-ubuntu-lts.md`
- `install-statbus.md:77`
- `hetzner-bootstrap.md:173,179`
- `create-new-statbus-installation.sh:36,182`
- `ops/niue/sshdoers:4`
- `service.go:2442`

Also use `tmp/harness-checkout-noise.md`. Hetzner provides Ubuntu 26.04 images
for both x86 and Arm.

## 2026-09-23 harness-half progress

Implemented locally in two commits, without pushing: the shared VM bootstrap
defaults to Hetzner `ubuntu-26.04`, while exactly `0-happy-upgrade` pins
`ubuntu-24.04`. The candidate fresh install therefore tests the new-install path
on 26.04, while the previous-release-to-candidate happy upgrade tests the path
the 24.04 fleet actually takes. All recovery scenarios and upgrade arcs remain on
26.04. Offline contract tests cover that matrix. Documentation now distinguishes
configured coverage from readiness and records that the current setup script
warns, but does not refuse, when `VERSION_ID` is not `24.04`.

The harness half is awaiting the coordinator's push after independent review.
Ubuntu 26.04 readiness remains unproven until the first paid install-recovery
and upgrade-arc runs execute on real Hetzner VMs.

## Workstreams

- **A: this ticket.** Preserve the Finland transcript, defects, decisions, and
  acceptance boundary in the backlog.
- **B: setup split and D1-D7.** Implement the public/fleet separation and repair
  every still-open transcript defect. This work is carried by rc.19.
- **C: harness contract.** Make Ubuntu 26.04 primary, keep exactly the happy
  previous-release-to-candidate upgrade on the fleet's Ubuntu 24.04, and install
  by VERSION with an optional commit debug override.
- **D: live proof.** Run the resulting matrix on VMs and retain the evidence.

## 2026-09-23 setup-half progress

D4 is resolved locally. The version-neutral `ops/setup-ubuntu-lts.sh` has one
supported-version gate for Ubuntu 24.04 and 26.04. It refuses every other
release before setup in both interactive and non-interactive mode. Repository
references now use the version-neutral name, and an os-release fixture test
covers acceptance of 24.04/26.04 and refusal of 22.04/25.10. Live package and
repository proof on both supported releases remains the install-recovery
harness run.

## Done when

1. The public script contains only public hardening, Docker, and the `statbus`
   service account; it requires no GitHub credentials, exposes no fleet terms,
   uses HTTPS only, and completes without warnings on its supported path.
2. The layered SSB cloud script owns `devops`, GitHub key retrieval,
   `SSHDOERS_REF`, and all other fleet-only setup.
3. D1-D7 are each covered by an executable regression test, including fail-fast
   behavior before account creation when required key material is absent.
4. Service-account authorized keys can be supplied by both paste and file/env.
5. Every setup summary statement is derived from the actual stage result; no
   skipped step is reported as installed.
6. The harness uses Ubuntu 26.04 as primary, retains exactly one Ubuntu 24.04
   happy-upgrade path from previous release to candidate on the fleet's Ubuntu
   24.04, and uses VERSION/rc-tag checkout by default.
7. The x86 and Arm VM matrix runs to completion and records public setup,
   fleet-layer setup, fresh install, and service readiness evidence.
8. The stale `devops@<host>` and Linuxbrew `PATH` references are corrected, and
   all rename-impact sites in the implementation inventory are reconciled.
9. rc.19 carries Workstream B, and the release evidence links this ticket and
   STATBUS-369.

## rc.19 checkpoint and deferral (2026-09-19)

Status remains **open**, deliberately deferred until a green stable exists. The
rc.19 installer fixes in `9e57c1722` are live on statbus.org, and Finland's
blocking D8-D11 are fixed. D1-D7, the public/fleet setup split, and the harness
work remain pending for rc.20 or later.

## Current disposition and live installer evidence (2026-09-20)

This ticket remains **OPEN** and is deferred until a green stable exists, per
the owner's 2026-09-19 ruling.

The rc.19 installer fixes were live-verified by Norway's rc.20 installation.
The real operator path proved channel resolution, clean detached checkout,
signer flow, and inline dispatch green. Separately, `cloud.sh` now
automatically logs mutating verbs (`d032588e5`), as requested by the owner.
These facts reduce installer-path uncertainty but do not complete the Finland
Ubuntu 26.04 setup split or its remaining D1-D7 acceptance work.

## Update 2026-09-22

The release readiness probe in `cli/cmd/release/release.go`
(`verify-artifacts` calling `CheckReleaseWorkflowAtTag`) treats an empty GitHub
API workflow-runs page as `Missing`, the same result used for "workflow not
started". This was observed at 2026-09-22 14:39Z; the workflow was green three
minutes later. Add a bounded retry for the `Missing` case before presenting the
not-started remedy, so a transient empty API page is not classified as durable
absence.

## 2026-09-24 Finland v2026.09.2 install

The new install triage confirms that the preflight disk refusal still surfaced as
`SYSTEM UNUSABLE / no named invariant`, despite this ticket's earlier record
that the `SYSTEM UNUSABLE` handling for preflight refusals was fixed in
`9e57c1722`. The evidence is the Finland transcript analyzed in
`tmp/finland-install-triage.md`, with the abort path at `install.sh:770-792`
and the intended refusal type at `cli/cmd/install.go:95-101`. Keep this ticket's
D8-D11 closure claim scoped to the earlier installer fixes and track the disk
refusal regression separately as STATBUS-386, where the target is a plain
preflight message that states free space, required space and the command to
continue. The north star for the Finland follow-ups: a third-party operator
follows the instructions on a fresh Ubuntu 26.04 host and ends with every
service running (STATBUS-384 to STATBUS-394).

## Reconciliation 2026-09-23

Classification: PARTIAL. Evidence: 9e57c1722 release fixes plus master-only 9032d89d5, bb5885f9c and be28245af; public/fleet setup split and complete VM matrix remain.

Remaining: Complete public/fleet setup split, D1-D7, x86/Arm 26.04 matrix, and bounded retry for an empty GitHub workflow-runs page. Master-only OS/setup fixes ship next release.

Readiness probe fact: `CheckReleaseWorkflowAtTag` currently maps an empty GitHub workflow-runs API page to `Missing`/workflow-not-started. Add bounded retry before declaring durable absence; this was observed on 2026-09-22 and the workflow appeared green three minutes later.

Pending niue owner action: update the installed `/etc/sshdoers` comment from `ops/setup-ubuntu-lts-24.sh, byte for byte` to `ops/setup-ubuntu-lts.sh, byte for byte` and run Stage 8 on niue when the setup rename lands there.
