---
id: STATBUS-376
title: >-
  Third-party install on Ubuntu 26.04 (Finland NSO): install defects + setup
  split
status: To Do
assignee: []
created_date: '2026-09-18 17:48'
updated_date: '2026-09-22 17:01'
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
Ubuntu 26.04 LTS. As `statbus`, he ran `setup-ubuntu-lts-24.sh`, then:

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
   the current static summary is at `setup-ubuntu-lts-24.sh:1690`.
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
3. **Ubuntu 26.04 LTS is the primary harness image.** Retain exactly one Ubuntu
   24.04 bare-install happy path. Readiness is established by running the
   harness, not by analysis.
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
- `setup-ubuntu-lts-24.md`
- `install-statbus.md:77`
- `hetzner-bootstrap.md:173,179`
- `create-new-statbus-installation.sh:36,182`
- `ops/niue/sshdoers:4`
- `service.go:2442`

Also use `tmp/harness-checkout-noise.md`. Hetzner provides Ubuntu 26.04 images
for both x86 and Arm.

## Workstreams

- **A: this ticket.** Preserve the Finland transcript, defects, decisions, and
  acceptance boundary in the backlog.
- **B: setup split and D1-D7.** Implement the public/fleet separation and repair
  every still-open transcript defect. This work is carried by rc.19.
- **C: harness contract.** Make Ubuntu 26.04 primary, keep exactly one Ubuntu
  24.04 bare-install happy path, and install by VERSION with an optional commit
  debug override.
- **D: live proof.** Run the resulting matrix on VMs and retain the evidence.

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
   bare-install happy path, and uses VERSION/rc-tag checkout by default.
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
