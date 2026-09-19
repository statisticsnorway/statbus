---
id: STATBUS-377
title: >-
  rc.18 boxes cannot self-upgrade: pre-pull capture runs in the OLD binary
status: To Do
assignee: []
created_date: '2026-09-19 10:43'
updated_date: '2026-09-19 10:43'
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

## Proven operator rescue path

Document this break-glass inline path in both `doc/CLOUD.md` and
`doc/DEPLOYMENT.md`:

1. Fetch the target tag on the affected box.
2. Extract the new `sb` from
   `ghcr.io/statisticsnorway/statbus-sb:<commit_short>` using `docker create`
   and `docker cp /sb`.
3. Atomically preserve and swap `sb` and `sb.old`.
4. Restart `statbus-upgrade@<slot>` so the unit loads the new binary.
5. Run `./sb upgrade register <version>` and
   `./sb upgrade schedule <version>`.

This procedure recovered the 2026-09-19 dev canary. It must be precise about
ownership, permissions, rollback of the binary swap, slot naming, and how to
confirm that the restarted unit is actually running the target binary.

## Design question

Choose and encode a durable boundary:

1. Have `executeUpgrade` verify/capture the current installation with logic from
   the target tree or target binary, while still reading the current compose
   configuration and current serving image identities; or
2. Minimize the pre-pull phase to operations whose correctness cannot depend on
   features or bug fixes introduced by the target release.

A solution must account for the fact that target code is not yet trusted or
fully installed, while also ensuring that a defect in an old release cannot
permanently prevent that release from upgrading to its repair.

## Done when

1. `doc/CLOUD.md` and `doc/DEPLOYMENT.md` contain the tested operator rescue
   procedure, including target-tag fetch, image extraction, safe binary swap,
   unit restart, registration, scheduling, verification, and rollback guidance.
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
