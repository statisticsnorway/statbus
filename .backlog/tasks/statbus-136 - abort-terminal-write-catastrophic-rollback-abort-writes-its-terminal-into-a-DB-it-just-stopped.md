---
id: STATBUS-136
title: >-
  abort-terminal-write: catastrophic rollback abort writes its terminal into a
  DB it just stopped
status: Done
assignee: []
created_date: '2026-07-04 22:31'
updated_date: '2026-07-07 00:22'
labels:
  - upgrade
  - install-recovery
  - product
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/exec.go
  - STATBUS-044
ordinal: 137000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: even the catastrophic rollback-abort path concludes cleanly — the terminal write must land.
> BENEFIT: removes a structurally-guaranteed death loop observed live (r17: abort wrote its terminal into the DB it had just stopped, ×3) — the difference between a box that ends in a named failed state and one that restarts forever on a path that already concluded.
> STAGE: Stage 1 (r17 live finding; fix shape ruled: start the DB before the terminal write).
> COMPLEXITY: engineer-substantial (small diff on the abort path; safety-critical, architect reviews).
> DEPENDS ON: nothing. Its future oracle is the rollback-crash-loop scenario noted on STATBUS-044's ledger.

---

FOUND live in r17 (2026-07-05): the git-restore ABORT path ([ROLLBACK_FAILED_GIT_CORRUPT]) stopped services (incl. db) for the restore, then attempted the terminal row write against the stopped DB → connection EOF → INVARIANT ROLLBACK_TERMINAL_WRITE_FAILED, flag kept, process exit → guaranteed death + systemd restart on a path that had already concluded. The terminal write can never succeed in that ordering. Repeated ×3 in r17 (each pass re-ran the whole abort). FIX SHAPE (architect): on the abort path, bring the DB back up BEFORE the terminal write — StartDBForRecovery-style `docker compose start db` (the asymmetric-safe start-existing primitive, never up -d) + the existing bounded write retry. The restore never ran (that is what aborted), so the DB volume is untouched and starting the existing container is safe by the same argument as install crash-recovery's connect-first pattern (cli/cmd/install_upgrade.go:192-219). Evidence: r17 journal on the kept VM / tmp logs. Verification: unit-level ordering guard (db-start precedes terminal write on the abort path) + the future rollback-crash-loop scenario (STATBUS-134's natural oracle) asserts the terminal actually lands.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NORTH STAR: a failed rollback must be able to RECORD that it failed — the box's last honest act before summoning a human. SHIPPED 4058ab2ce (2026-07-07): the abort branch starts the existing db container (compose start, never up -d) and waits for health before its state='failed' terminal write, best-effort with loud warnings — killing the r17-observed x3 death loop (terminal write against a stopped DB → invariant → exit → systemd rerun) while preserving every loud-failure property. Architect verified all three volume states safe (restored / untouched / partial — partial fails health into the same loud terminal; compose start never rewrites volume data) and that cancellation cannot skip the write. Ordering pinned by structural test. LIVE ORACLE: the STATBUS-134 pair-terminal rollback-crash-loop scenario (071 campaign U4) asserts the restore-broke terminal actually lands — this fix is its prerequisite.
<!-- SECTION:FINAL_SUMMARY:END -->
