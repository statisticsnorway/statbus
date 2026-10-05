---
id: STATBUS-444
title: >-
  Install crash recovery regenerates config without migrating legacy secrets, so
  a 09.2-era box stops mid-upgrade
status: In Progress
assignee: []
created_date: '2026-10-03 10:05'
updated_date: '2026-10-05 09:38'
labels:
  - upgrade
  - install
  - recovery
  - config
dependencies: []
references:
  - STATBUS-361
  - STATBUS-436
  - STATBUS-445
priority: high
---

## Issue

The official sequence is register, then schedule (daemon down), then a version-pinned `install.sh`, then `./sb install` inline-dispatches the row. On a box whose `.env.config` still holds legacy secrets, it stops after the binary swap, inside maintenance:

    M 09:52:00   Replacing ./sb with the v2026.10.0-rc.13 binary (./sb.old kept for rollback) ... ok
    M 09:52:00   Old binary exiting so the new binary can take over ...
    The previous upgrade stopped unexpectedly. Recovery will run now.
    Error: SLACK_TOKEN in .env.config is a secret; run cd /home/statbus/statbus && ./sb install to migrate it to .env.credentials
    Installation stopped: crash recovery: crash recovery: regenerate config: exit status 1: ...

v2026.09.2 and earlier write `SLACK_TOKEN` and `SEQ_API_KEY` into `.env.config` themselves.

## Mechanism

- After the swap the old binary `syscall.Exec`s the new one. The new binary re-enters `./sb install`, and `runCrashRecovery` (cli/cmd/install_upgrade.go ~336) runs `./sb config generate` **without** `--migrate-legacy-secrets`.
- `loadOrGenerateConfig` (cli/internal/config/config.go ~368) refuses on the secret.
- The upgrade service's own recovery boot already passes the flag (service.go ~3001, ~10255; f8503adca, STATBUS-361). The install recovery path was missed.
- The plain install path is unaffected: its Settings step uses `GenerateForInstallInDir`, which migrates first.

## Scope

- **Affected:** any box whose `.env.config` still holds legacy tokens when `./sb install` inline-dispatches a scheduled upgrade. Probe 2026-10-03 shows these boxes in that state: demo (09.2), et (09.0), ug (09.0), jo (08.0).
- **Not affected:**
  - the version-pinned install with no scheduled row (`./cloud.sh install`): the 436 operator path passed on rc.12 and rc.13
  - the daemon's own upgrade
  - 09.3+ boxes, whose secrets have already moved

## Evidence

The 436 scheduled-path proof against v2026.10.0-rc.13 (2026-10-03 09:42–10:00 UTC), guest `…-39285`. Evidence: `tmp/436-scheduled-rc13-evidence/` (`statbus-tmp/install-last-run-output.txt`). The same run confirmed the 441 and 443 fixes live: the floor applied, the claim succeeded, and capture said "Recording immutable source image identities ... ok".

## Principled fix

Pass `--migrate-legacy-secrets` at the install crash-recovery `config generate`. That is an install/upgrade context, exactly what the flag is for, and it matches the service path. Audit every other `config generate` call site for the same exposure, and record a verdict per site.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The install crash-recovery path invokes config generation with legacy-secret migration, pinned by a behavioral test (recorded command line or seam), not a source grep.
- [x] #2 Every `config generate` call site in cli/ has a recorded verdict (needs the flag / cannot see legacy secrets / old binary that lacks the flag), and those that need it pass it.
- [ ] #3 The STATBUS-436 scheduled-path guest proof passes against the candidate carrying the fix (this also closes 443 AC#3, 441 AC#2 and 436 AC#5).
<!-- AC:END -->

## Implementation Notes

2026-10-03 19:22 UTC: the first fix (4575c5e22, `--migrate-legacy-secrets` in install crash recovery) was BLOCKED in review (`tmp/444-review.md`).
- Moving SLACK_TOKEN/SEQ_API_KEY into `.env.credentials` mid-upgrade breaks rollback to v2026.09.2. 09.2 reads them only from `.env.config`, so after a rollback its config generate writes placeholders back, and Slack/Seq credentials are silently lost.
- The same defect has been latent in shipped code since STATBUS-361 (f8503adca), in v2026.09.3 and rc.13. The service path already does this move, and rollback restores the DB and git but never the operator config files.

2026-10-05 owner decision: snapshot. Snapshot `.env.config` and `.env.credentials` before target code can rewrite them, and restore both on every rollback to the source.

Owner requirement on the same day: **delete the snapshot once the upgrade is terminal**, both on completion and after a rollback has restored from it. Secret-bearing leftovers are a real risk. Keep it while any recovery could still need it. When a new upgrade finds a stale snapshot, it replaces it atomically.

Implementing on branch `fix/444-config-snapshot` (carries 4575c5e22 as 5f59a6762).

2026-10-05 owner refinement (supersedes the separate-cleanup design): store the config snapshot **inside the database backup** (`pre-upgrade-active/operator-config/`, written into the syncing dir after rsync and before the fsync + atomic rename), so it follows the backup's existing lifecycle: committed atomically with it, replaced by the next backup, and pruned with it. No separate retention or deletion logic. Every rollback path that restores from `backup_path` also restores the two files before the source's config generate runs.

2026-10-05 08:52 UTC, review trail on branch `fix/444-config-snapshot`:
- 7f805e801 (snapshot inside backup): BLOCK. An old-format backup without a snapshot hard-failed rollback, park restoration, and the STATBUS-111 replay. Everything else passed: ordering, PGDATA exclusion, lifecycle, 0700/0600 security, and source-return ordering.
- aac7cb2cd (degrade safely): BLOCK. The old-backup case is fixed, but a valid-JSON incomplete manifest (`{}`) would zero-fill missing entries to "absent" and DELETE both current operator files. The fix being built: a versioned manifest with required explicit records, everything validated before any write, invalid → degraded with files untouched, plus behavioral tests through both chokepoints.
- STATBUS-445 (8bebcad33 config ordering fix + 402789fcf fixtures/rollback test): MERGE (`tmp/445-review.md`).

Review files: `tmp/444-review.md`, `tmp/444-snapshot-review.md`, `tmp/445-review.md`.

2026-10-05 09:20 UTC: two more review rounds, both BLOCK, on the same destructive class.
- d08cefdfd: a record's `present` could be omitted and zero-fill to false.
- db8d86549: Go `encoding/json` matches keys case-insensitively, so `"Present"` or `"Env_Config"` satisfy or shadow the canonical keys and slip past the duplicate check. In every case a manifest can be read as "absent" and delete the current `.env.config`.

Decision: stop hardening the JSON decode. Replace it with a layout where absence is a positive marker and cannot be the result of parsing:
- each file is exactly one of `<name>.present` (the byte-exact content) or `<name>.absent` (an empty marker)
- a fixed `FORMAT` file holds a version string
- validation checks the exact set of entry names, regular files only (no symlinks)
- any deviation → degraded, both files untouched, the rollback continues

2026-10-05 09:38 UTC: the v2 marker-file layout (2845e302f) passed adversarial re-review (MERGE, `tmp/444-snapshot-review.md`). The reviewer:
- confirmed that removal happens only from an exact, empty, canonical `.absent` regular file, after full validation
- confirmed that every malformed layout degrades before any change
- confirmed that the restore uses the in-memory bytes it validated, so there is no check-then-use race
- ran the case-variant subtest on Linux in Docker (`golang:1.25-bookworm`): PASS

Merged onto master as 02439a311, 177e62434, 6739fa480, f521a32d4, 9635cd56d and ff7408815. Every patch-id equals its reviewed commit.

The full `go test ./...` on the merged tree first failed on `TestEveryTestGitHelperUsesThisPackage`: the snapshot test called git directly instead of through the sanctioned helper. Fixed in a separate test commit that routes it through `internal/testgit`, independently checked. After that, all packages pass.

AC#1 and AC#2 are met. AC#3 (the scheduled-path guest proof) runs against rc.14.
