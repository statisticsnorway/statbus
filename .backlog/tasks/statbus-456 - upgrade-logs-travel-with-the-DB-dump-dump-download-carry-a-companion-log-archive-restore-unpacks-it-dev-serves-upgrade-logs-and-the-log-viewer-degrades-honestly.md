---
id: STATBUS-456
title: >-
  upgrade logs travel with the DB dump: dump/download carry a companion log
  archive, restore unpacks it, dev serves /upgrade-logs, and the log viewer
  degrades honestly
status: In Progress
assignee: []
created_date: '2026-10-07 11:13'
updated_date: '2026-10-07 11:44'
labels:
  - cli
  - db
  - frontend
  - upgrades
dependencies: []
priority: high
ordinal: 386201
---

## Status: OWNER APPROVED 2026-10-07 ("A1++ approved"). Implement as specified; the design was agreed in discussion and is not open for re-litigation.

## Zoom out: why this exists

An upgrade log lives on the box's disk; the ledger row only carries its path
(`public.upgrade.log_relative_file_path`). So the moment you take a database dump
somewhere else, every log reference dangles.

Observed 2026-10-07 while visually testing the new admin Upgrades page
(STATBUS-455) against a restored Demo dump: the serving card opens its log by
default and showed

```
Failed to load log: HTTP 404
```

That single symptom has **three independent causes**, and this ticket fixes all
three so local behaves like the box:

1. **No data.** `./sb db restore demo_…pg_dump` restores rows, not `tmp/upgrade-logs/`.
   Row 227495 points at `227495-v2026.10.0-rc.20-20261007T095028Z.log`, which only
   exists on Demo's disk. No amount of frontend work can show a file that is absent.
   The same is true for `tmp/install-logs/…` (the card's `Installs` disclosure and
   `system_info.install_last_log_relative_file_path`).
2. **No route in dev.** `app/next.config.js` rewrites only `/rest/:path*` to the dev
   Caddy target. `/upgrade-logs/*` is a Caddy route
   (`caddy/config/development.caddyfile:127`, `handle /upgrade-logs/*`), so
   `http://local.statbus.org:3000/upgrade-logs/<file>` 404s even with the file present.
3. **Dishonest failure render.** A missing log is displayed as a red
   `Failed to load log: HTTP 404`, on a section that the serving card opens by default.

## What exists today (verified references at bce5bf39 plus local commits)

CLI (`cli/cmd/db.go`):
- `db dump` (command at :89-119), `db download <code>` (:266-330), `dumps list` (:349),
  `restoreLocal` (:537), `restoreRemote` (:871), `ensureDumpsDir` (:155),
  `warnIfManyDumps` (:164, globs `*.pg_dump` only — companion files must not disturb it),
  `humanSize` (:175).
- Dumps live in `<projDir>/dbdumps/`.

Log producers/consumers:
- `upgradeLogsDir(projDir)` = `tmp/upgrade-logs` and `installLogsDir(projDir)` =
  `tmp/install-logs` (`cli/internal/upgrade/progress.go:68,72`); naming
  `<id>-<safe_version>-<ts>.log` (`:17-22`); per-upgrade siblings `.bundle.txt` and
  `.containers`; a best-effort `latest` symlink (`:232`).
- **Retention:** `pruneUpgradeLogs(20)` — 20 newest log+bundle pairs
  (`cli/internal/upgrade/exec.go:1278`, called at `cli/internal/upgrade/service.go:3716`).
  `tmp/upgrade-logs/` is therefore bounded.
- **`tmp/install-logs/` is NOT pruned** — it grows one file per install invocation.
- Served to the browser by Caddy at `/upgrade-logs/*` (read-only), fetched by
  `UpgradeLogViewer` in `app/src/app/admin/upgrades/page.tsx`.
- `cli/cmd/support.go:139-150` picks the newest `.log` in `tmp/upgrade-logs/`.

## Deliverable

### A1 — the logs travel with the dump

Companion archive next to the dump, named after it: `dbdumps/<stem>.pg_dump` +
`dbdumps/<stem>.logs.tar.zst` (zstd, falling back to `.tar.gz` when the `zstd`
binary is unavailable, with the extension matching the format actually written).

- **`./sb db dump`** — after the pg_dump succeeds, write the companion containing:
  - all of `tmp/upgrade-logs/` **except** the `latest` symlink (never ship a
    dangling link);
  - only the `tmp/install-logs/` files **referenced by the dumped database** —
    i.e. every non-null `public.upgrade.log_relative_file_path` whose value starts
    with `install-logs/`, plus `system_info`'s
    `install_last_log_relative_file_path` — because that directory is unbounded.
  Print the file count and byte size. An empty/missing directory is not an error:
  write a valid empty archive and say so.
- **`./sb db download <code>`** — after the remote dump downloads, stream the
  remote archive straight into the companion (no remote temp file), e.g.
  `ssh <target> "cd statbus && tar -C . -czf - <resolved relative paths>"`.
  Resolve the referenced `install-logs` set on the remote (the box has `./sb psql`).
  A stream that produces zero bytes must not leave a bogus companion file.
- **`./sb db restore <file>`** — when the companion exists next to the dump, unpack
  it into the project's `tmp/`, **merging**: never delete or overwrite unrelated
  local files, never fail the database restore because logs are absent. Print how
  many files were restored and where. When the companion is missing, print one clear
  line saying logs were not included in this dump.
- **`./sb db dumps list`** — show whether each dump has a companion, and its size.
- **`./sb db dumps purge [N]`** — treat dump+companion as one unit; never delete a
  companion without its dump or vice versa.
- **Ordering matters:** dump first, then archive, so the archive can only be newer
  than the rows. A missing log stays missing; an archive never claims a log for a
  row the dump does not contain.
- `db restore --to <code>` (remote restore) is **out of scope** — do not upload the
  companion to a box in this ticket; state that in the report.

### A2 — dev serves the same log route as a real box

Add a dev-proxy rewrite in `app/next.config.js` beside the existing `/rest` rule
(same `caddyTargetForRewriteRule` guard and same "no target configured → no rewrites"
behaviour):

```
source: '/upgrade-logs/:path*'  →  `${caddyTargetForRewriteRule}/upgrade-logs/:path*`
```

Rationale: in development the browser must reach the same route it reaches in
production, instead of a dev-only absence.

### A3 — the viewer degrades honestly

In `UpgradeLogViewer` (page.tsx): an HTTP 404 (log genuinely not in this copy)
must render a plain statement such as
`This log is not available in this copy of the database.` — not
`Failed to load log: HTTP 404`. Any other failure keeps its current, real error
message. The serving card's log-open-by-default must not present a missing log as
an error box.

## Constraints and non-goals

- Local code and tests only: no live boxes, no SSH to Demo/Norway, no installs,
  upgrades, channels or config changes. Do not run a remote `db download` against a
  production box to prove it; a local fake/`tar` fixture is enough.
- No schema change, no log content stored in the database, no change to the
  `pruneUpgradeLogs(20)` retention, no new pruning for `tmp/install-logs/`.
- Keep `warnIfManyDumps` and every existing dump/restore safety behaviour intact
  (atomic restore, TOC phases, auth-user handling).
- Logs leave the box inside a file next to the database dump; note in the docs that
  the companion is as sensitive as the dump itself.
- Commit with a `db:` / `upgrades:` prefix. Leave `.backlog/tasks/statbus-448` and
  `.yarn/` alone.

## Considered and rejected: rsync instead of a tar archive (2026-10-07)

Raised by the owner ("must of course use rsync, and with delete"), and rejected on
measurement:

```
tmp/upgrade-logs payload          64 KB
tar -C . -czf /dev/null …         0.015 s      (fifteen milliseconds)
for scale, a Norway dump          1.1 GB       (dbdumps/no_20260210_105613.pg_dump)
```

The logs are ~0.006 % of the transfer, and `tmp/upgrade-logs/` is bounded by
`pruneUpgradeLogs(20)` with only referenced install-logs travelling, so the payload
stays in the KB-to-low-MB range. A single streamed `tar` is therefore not a cost, and
rsync would add three real costs: `--delete` contradicts this ticket's merge-never-
delete restore rule (it would wipe a local box's own evidence when pulling someone
else's dump), `rsync` must exist on every box (`tar` always does), and a mirrored
directory loses the one-artifact-tied-to-one-dump-instant provenance. If download
speed ever matters, the levers are on the dump side (`pg_dump -j`, faster compression,
resumable transfer), not here.

## Verification: test with the DEMO dump, not Norway (owner, 2026-10-07)

Owner direction to save time: prove this feature against a `demo` dump, not the
1.1 GB Norway dump. Correct scope split:

- **STATBUS-456 (this ticket)** — demo is sufficient and is the chosen path:
  `./sb db download demo`, restore locally, then confirm the serving card renders the
  rc.20 log inline instead of "not available".
- **STATBUS-421 (export timeout)** — demo CANNOT prove that: it has only 144
  statistical units, so deep `OFFSET` + `count=exact` never approaches the 120 s
  statement timeout. 421's local repro needs the Norway dump or a synthetic
  >100k-row set; do not let a green demo run stand in for it.

## Local verification recipe (used to open this ticket)

```
./sb db restore demo_20261007_124616.pg_dump     # rows only today
cd app && pnpm run dev                            # http://local.statbus.org:3000
# /admin/upgrades → serving card → Log → "Failed to load log: HTTP 404"
```
After this work the same sequence must show the rc.20 log inline.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `./sb db dump` writes `<stem>.pg_dump` + `<stem>.logs.tar.zst`; the archive
      contains `tmp/upgrade-logs/**` (minus the `latest` symlink) and only the
      referenced `tmp/install-logs/**` files; count and size printed.
- [x] #2 `./sb db download <code>` produces both files locally, with the archive's
      member paths rooted at the project dir (`tmp/upgrade-logs/...`).
- [x] #3 `./sb db restore <stem>.pg_dump` unpacks the companion into `tmp/`, merges,
      prints counts, and succeeds with an explicit note when the companion is absent.
- [x] #4 A dump without logs, and a dump whose companion is deleted, both restore cleanly.
- [x] #5 `dumps list` and `dumps purge` treat the pair as one unit.
- [x] #6 In `pnpm run dev`, `http://local.statbus.org:3000/upgrade-logs/<existing file>`
      returns the file (rewrite works), and a missing file still 404s.
- [x] #7 The admin page shows "not available in this copy" for a missing log, and the
      serving card no longer renders a red HTTP 404 on load.
- [x] #8 Tests: Go tests for archive creation/restore/merge/missing-companion and for
      the referenced-install-logs selection; Jest tests for the 404 wording and for
      a non-404 error still showing its real message.
- [x] #9 Docs: `doc/DEPLOYMENT.md` (or the CLI help text) states that dump/download
      carry the logs and `restore` unpacks them, and what happens when they are absent.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented in commit 5dbf0f4f60885708ca4cbf2cf53c4f2d41700a96 (db: upgrade logs travel with the DB dump).

A1: new cli/internal/dbdump/logarchive.go core (WriteLogsCompanion / RestoreLogsCompanion / FindLogsCompanion / ReferencedInstallLogsSQL). db dump writes <stem>.logs.tar.zst (gzip fallback when zstd binary absent) after pg_dump succeeds; db download streams the remote tar.gz straight into the companion via ssh bash -s (no remote temp file, zero-byte stream leaves no file); db restore unpacks into tmp/ merging, never fails on absent logs; dumps list shows companion size; DumpsToPurge/PurgeDumps treat the pair as one unit. .gitignore now ignores companion archives.
A2: /upgrade-logs/:path* dev rewrite added beside /rest in app/next.config.js, same guard.
A3: UpgradeLogViewer tracks fetch status and renders 'This log is not available in this copy of the database.' on 404 via app/src/app/admin/upgrades/upgrade-log-message.ts; other failures keep the real message.

Verified live locally: real db dump wrote companion (6 files, 11.8 KB, incl. nested .containers/ logs); real restore unpacked it (6 files merged); a companion-less copy restored cleanly with the explicit note; dev proxy served an existing log (200) and 404'd a missing one with an authenticated session.

Validation: go test ./internal/dbdump/ ./cmd/ ok; go test ./internal/upgrade/ has one pre-existing failure (TestTypedComposeAuthorityGate) also failing on clean HEAD; app pnpm lint 0 errors (5 pre-existing warnings), tsc clean, jest 74/74 pass; prettier clean on touched files (repo-wide prettier has 248 pre-existing failures).

Not done per constraints: db restore --to <code> does not upload the companion (out of scope); db download not run against a real box (no SSH per constraints) - remote streaming path is code-reviewed but only the local tar fixture path is executed.
<!-- SECTION:FINAL_SUMMARY:END -->
