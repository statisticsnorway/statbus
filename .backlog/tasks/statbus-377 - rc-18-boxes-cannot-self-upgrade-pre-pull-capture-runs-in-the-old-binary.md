---
id: STATBUS-377
title: >-
  rc.18 boxes cannot self-upgrade: pre-pull capture runs in the OLD binary
status: Done
assignee: []
created_date: '2026-09-19 10:43'
updated_date: '2026-09-23 15:10'
labels:
  - upgrade
  - recovery
  - release
  - cli
  - compose
  - fail-fast
dependencies: []
references:
  - a96751064
  - 7244856d5
priority: medium
type: bug
ordinal: 1
---

## Incident (2026-09-19)

The dev canary deployment from rc.18 to rc.19 failed before pulling the target:

    Could not record immutable source image identities ... restored source compose config has no image for app

Master already fixes the underlying compose-render defect in `a96751064`, but an
installed rc.18 box cannot reach that fix through its own upgrade service.

## Code-verified root cause

`executeUpgrade` in `cli/internal/upgrade/service.go:7079` writes the recovery
flag at approximately line 7280 and calls
`captureSourceServingImageIdentities` at approximately line 7287. Both happen
before the target pull and long before `replaceBinaryOnDisk` and exit 42 restart
the daemon under the target binary.

Therefore the running daemon's **old installed binary** executes all pre-pull
capture behavior. Any defect in that phase can strand the release containing
it: the box must successfully execute the broken old code before it can obtain
or run the repaired code.

rc.18 (`7244856d5`) has exactly such a defect. Its compose render omits
`--profile all`, so profile-gated services have no rendered image. Every rc.18
box consequently fails every normal upgrade during pre-pull source-image
capture, including an upgrade to a release containing the fix.

The capture's data direction is correct: it must inspect the **current serving
installation**. The defect is that successful escape depends on the old
binary's rendering behavior. Nothing structural currently prevents another
release from introducing the same class of self-stranding pre-pull bug.

## Remedy (the only approved path)

Re-run the official installer on the box:

    curl -fsSL https://statbus.org/install.sh | bash

Use the box's channel equivalent where applicable. `install.sh` downloads the
**new binary first**; `./sb install` (new binary) detects state and dispatches the
pending upgrade inline, so every phase runs new code.

This is the only upgrade advice given to operators and the only path SSB uses
itself. It is channel-driven: for example, `--channel prerelease` resolves the
newest candidate. It is never a version pin; the fleet orchestrator's
newest-check guards supersession.

Any other path, including manual binary swaps, is a rare exception requiring
the owner's personal approval. For the record, a manual binary swap was
performed on dev on 2026-09-19 before this ruling. It is not a precedent.

## Open question

STATBUS-378 (served `install.sh` box-binary compatibility) is the prerequisite
fix. The remaining question is whether `deploy-to-dev` and any other fleet
automation invokes the installer by channel everywhere (the `deploy-to-dev` fix
is in flight), and whether `doc/CLOUD.md`, `doc/DEPLOYMENT.md`, and
`doc/upgrade-recovery-model.md` state the installer-rerun remedy prominently
enough that an operator hitting a stranded box finds it without support.

## Done when

1. STATBUS-378 ensures the served `install.sh` downloads a box-compatible new
   binary before invoking `./sb install`.
2. The upgrade design states which binary/tree owns every pre-pull operation and
   why an old defect cannot strand the installed release before target code can
   take over.
3. Source-image capture still records immutable identities for the currently
   serving installation, not identities inferred from the target installation.
4. An executable regression starts from rc.18 (`7244856d5`) or an equivalent
   old-binary fixture with the profile omission, upgrades to a fixed candidate,
   and proves that the fixed target takes over without manual source edits.
5. The regression exercises profile-gated `app` and other services and fails if
   compose rendering omits `--profile all` or yields a service without an image.
6. Recovery evidence proves the recovery flag, `sb`/`sb.old`, exit-42 handoff,
   service restart, source-image identities, and final serving version remain
   coherent across interruption and retry.
7. Release documentation names this compatibility boundary so future changes to
   pre-pull behavior require an old-to-new upgrade proof.
8. Fleet automation invokes the official installer by channel, never by version
   pin, and preserves the newest-candidate supersession guard.
9. `doc/CLOUD.md`, `doc/DEPLOYMENT.md`, and
   `doc/upgrade-recovery-model.md` prominently direct operators to re-run the
   official installer and do not prescribe a manual binary swap.

## Dev canary evidence and ruling (2026-09-19)

Dev canary rc.19 deployment run `35404014913` failed before pull in the old
binary. A manually swapped dev attempt was then made before the owner ruling; it
was a one-off and is not a precedent. That attempt reached the **next** check and
failed with:

    pre-upgrade app container image reference ... want current source compose reference

This proves source-image capture also assumed `tree == source`. The official
installer-rerun path violates that assumption by design because `install.sh`
checks out the target before dispatching the upgrade. A fix deriving the source
era from the running containers is in flight.

Owner ruling: the **only** approved upgrade path is re-running the official
installer. It is channel-driven, never version-pinned, and never manual binary
surgery. Any rare exception requires the owner's personal approval.

New open question: after the container-derived capture lands, does any other
pre-pull step still assume `tree == source`?

## 2026-09-20 disposition: incident closed, structural question remains open

The rc.18 old-binary stranding incident is **CLOSED as designed behavior with a
documented remedy**. The rc.18 boxes could not self-upgrade because pre-pull
capture runs in the installed old binary; the dev canary demonstrated the
failure in run `35404014913`. The owner's 2026-09-19 ruling is binding: the
**only approved recovery path** is to re-run the official channel-driven
installer, which downloads the new binary first. That path succeeded for
Norway's rc.20 install and the rc.20 dev canary.

The fixes that make the approved path trustworthy are:

- `a3577476f`: `install.sh` bootstrap no longer depends on the box binary.
- `7d0e8391e`: `deploy-to-dev` uses the channel installer; its required
  sshdoers entry is `63b1dabe9`, live on niue on 2026-09-20.
- `3d393d725` and `e9cf9d9f4`: capture source identities from running
  containers, guard the route tier as running, and allow the worker to be
  stopped.
- `ebbc53a12` and `2cb0ff6d4`: preserve captured marker identity across resume
  and corrupt-marker recovery.
- `cc079588b`: admission accepts intentional manual re-dispatch.

This ticket remains **OPEN at P2** only for the structural design question:
`executeUpgrade`'s pre-pull phase still runs in the old binary by design.
Consider whether source capture should move post-swap or be delegated to the
downloaded target binary. The documented installer rerun is the supported
remedy unless and until that boundary changes.

## Update 2026-09-22

Norway supplied the real-world instance of this boundary during the rc.28
attempt. The checkout, on-disk `sb`, generated environment, and serving
containers were rc.20, while `statbus-upgrade@statbus.service` still ran a
deleted rc.18 executable. Rc.18's source capture omitted `--profile all`, so
`app` disappeared from the Compose render and every rc.28 attempt failed before
claim/pull. The daemon reclaimed the failed row every 1-2 seconds: 190 attempts
were observed, followed by 360 attempts per 10 minutes, with
`recovery_attempts=0` and no park.

The operational remedy taken today was `./cloud.sh install no`, which puts the
new installer/binary in charge rather than asking the resident rc.18 daemon to
cross its own defect. The durable daemon/process identity invariant and bounded
park-class handling for pre-claim failures are tracked in STATBUS-382. Commit
`a96751064` fixes the profile render in newer binaries but cannot change an
already resident rc.18 process.

## Resolution 2026-09-23

Acceptance is met by 002b99d9f and subsequent old-binary/pre-pull repairs shipped and passed in v2026.09.1. The fix is released in v2026.09.1.

Pre-download policy fact: rc.31 was selected and downloaded before rc.30. The selector already compares CalVer correctly. The open policy question is whether to download only the latest candidate or a bounded descending set with an explicit resource budget and clear journal wording (`tmp/rc31-norway-observations.md` section 3).
