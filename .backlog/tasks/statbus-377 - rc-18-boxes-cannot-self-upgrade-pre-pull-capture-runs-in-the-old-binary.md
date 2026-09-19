---
id: STATBUS-377
title: >-
  rc.18 boxes cannot self-upgrade: pre-pull capture runs in the OLD binary
status: To Do
assignee: []
created_date: '2026-09-19 10:43'
updated_date: '2026-09-19 10:51'
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
priority: high
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
