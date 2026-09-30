---
id: STATBUS-436
title: Source image capture must use Docker container identity, not Compose display strings
status: In Progress
assignee: []
created_date: '2026-09-30 13:03'
updated_date: '2026-09-30 13:19'
labels:
  - upgrade
  - recovery
  - compose
  - field-report
  - cli
dependencies: []
references:
  - STATBUS-377
  - STATBUS-382
priority: high
type: bug
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Demo's v2026.09.2 daemon repeatedly attempts the upgrade to stable v2026.09.3. The owner observed continual front-page/maintenance-page switching on 2026-09-30. Source inspection explains the redirect window: each claim briefly exposes an `in_progress` row with `started_at` set and no error, which the app's upgrade guard redirects to the maintenance page. This mechanism is source inference, not a captured browser trace. The refusal occurs before Caddy's maintenance flag is set, so neither that flag nor the upgrade lock file explains the redirect. Read-only server inspection confirms a false source-version mismatch: Docker Compose's display image string is an image ID, but the container's original image reference still names the correct source commit.

### Live observations, 2026-09-30 12:58-13:02 UTC

- Checkout and on-disk CLI: `fe4a769a`, v2026.09.2.
- Worker container `.Config.Image`: `ghcr.io/statisticsnorway/statbus-worker:fe4a769a`.
- Worker container `.Image`: `sha256:5207b175fa080e47a942e236a29fe801113df99c634aaef2272d9d5e34fa1645`.
- App and proxy `.Config.Image` also name `fe4a769a`. All three are running and were created on 2026-09-24 around 14:21:05 UTC.
- The worker image's local RepoTags contains newer commit tags, including `ebe058af`, but no `fe4a769a` tag. Compose `ps --all` displays worker, proxy and db as `sha256:...` references. This is display/tag metadata drift, not evidence that the worker container was created from different source code.
- Supervised service PID 3408307 is active since 2026-09-24 14:20:50 UTC, with `NRestarts=0`. The observed loop is repeated attempts within one daemon, not a systemd restart loop.
- Target row 25829 (`ebe058af`, v2026.09.3) repeatedly records `failed`, then another upgrade starts about two seconds later. `failure_code`, `recovery_parked_at`, `recovery_parked_reason` and `backup_path` are null, `recovery_attempts=0`; `started_at` and the log filename change on each attempt.

The refusal reads:

```
Could not record immutable source image identities before target pull:
source serving era cannot be established: pre-upgrade source containers have mixed tags:
worker uses "5207b175fa080e47a942e236a29fe801113df99c634aaef2272d9d5e34fa1645",
want common source tag "fe4a769a"
```

### Source mechanism and released/unreleased boundary

`sourceServingContainerEntries` currently carries Compose's display `Image` field into `resolveSourceServingImageIdentities`. `extractImageTag` extracts the hex portion of `sha256:...` as if it were a repository tag. The common-source-tag check then rejects otherwise coherent containers. Source capture already inspects the Docker daemon's immutable `.Image`; the requested container reference must likewise come from the Docker daemon, with both fields checked coherently.

The common-tag guard was introduced in `3d393d725`. Its function body and source-entry producer are identical in v2026.09.2, v2026.09.3 and current master `0ff6a590c`. There is no released fix for this display-reference confusion, nor a fix in master at that commit.

There is a separate **released containment fix**: `5c1cb6046` is not an ancestor of v2026.09.2 but is included in v2026.09.3. The newer real source-capture error path parks the deterministic pre-destructive failure and removes its flag instead of repeatedly calling `failUpgrade`. That containment applies only after a v2026.09.3-or-newer binary runs, not to demo's resident v2026.09.2 daemon. Source inference suggests parking would stop the app's redirect window because the parked row carries an error, but it would not complete this upgrade. The official installer proof has not started: the on-demand LXD fleet box was reaped, and no reproduction guest exists. No installer outcome is claimed until a real guest run. Do not conflate idle parking with a completed upgrade.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria

<!-- AC:BEGIN -->
- [ ] #1 A regression reproduces the real condition: a container retains its named source `.Config.Image` and immutable image ID while Compose displays a `sha256:...` image string. Source capture succeeds using authoritative daemon identity, and the regression fails against the current implementation.
- [ ] #2 Capture and recovery retain their fail-closed behavior for genuine mixed source references, missing or ambiguous containers, invalid identities and incompatible immutable IDs. Neither checkout intent nor a current mutable image tag substitutes for the container's actual identity.
- [ ] #3 Related serving-version/canary paths are checked for the same display-reference confusion and, where affected, are corrected with behavioral regressions without weakening immutable source proof. The audit explicitly records affected/unaffected verdicts for the version check in `containers.go` (`extractImageTag(s.Image)`), `deriveServingEra` in `service.go` (target tag from `entry.Image`), and the serving-reference equality check in `service.go`.
- [ ] #4 A real LXD reproduction of the old released daemon loop exercises the official installer remedy and records whether it completes the upgrade, parks while serving the source, or refuses. Automatic retries do not continually re-enter maintenance after a deterministic refusal under the fixed program.
- [ ] #5 The product fix is independently reviewed and tested against its built candidate in a real LXD guest before being advertised as a released fix. Existing install/recovery safety invariants remain green.
- [ ] #6 Demo is repaired through a supported release-addressed path and observed over repeated availability checks and scheduler ticks, with recorded checkout/binary/resident-program/container identities and terminal upgrade state. A momentary HTTP 200 is not sufficient proof.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Initial diagnosis is read-only. No production container, tag, service, credentials, ledger row or maintenance flag has been changed. A code worker has a partial signed prototype in an isolated checkout; it has not completed validation or independent review. Installer proof is blocked before any guest execution because the fleet box was reaped. The cause of the missing local tag metadata is not determined. Two additional schedulers observed at 02:26 and 04:37 UTC have not been attributed to an actor. Missing local tags explain the Compose display fallback by source inference, not an observed Docker metadata deletion event.

Evidence reports are being collected under `tmp/demo-upgrade-incident-20260930.md` and `tmp/demo-installer-repair-proof-20260930.md`. Root observations above were captured by read-only SSH and are also present in the coordinator tool transcript.
<!-- SECTION:NOTES:END -->
