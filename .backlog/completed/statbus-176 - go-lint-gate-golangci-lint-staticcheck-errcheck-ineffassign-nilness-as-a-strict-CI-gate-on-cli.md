---
id: STATBUS-176
title: >-
  go-lint-gate: golangci-lint (staticcheck, errcheck, ineffassign, nilness) as a
  strict CI gate on cli/
status: Done
assignee: []
created_date: '2026-07-13 14:42'
updated_date: '2026-07-15 08:39'
labels:
  - ci
  - quality-gate
  - go
dependencies: []
priority: medium
ordinal: 177000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King-approved quality gate. Add golangci-lint to CI covering the Go CLI (cli/), with exactly these analyzers enabled: staticcheck, errcheck, ineffassign, nilness.

Shape (per the ratified strict-gating doctrine): a strict job that FAILS the workflow on any finding — no continue-on-error hedges. If a bypass is ever needed it must be loud and explicit (SKIP_GO_LINT=1 style), never a silently-tolerated red job.

Rollout: first run will surface a backlog of existing findings. Burn them down in the same unit or in an immediately-following series of small commits — do not land the gate in a permanently-red or bypassed state.

Config lives in cli/.golangci.yml so local `golangci-lint run` matches CI exactly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CI job runs golangci-lint on cli/ with staticcheck, errcheck, ineffassign, nilness enabled and fails the workflow on any finding
- [x] #2 No continue-on-error on the lint job; any bypass is an explicit loud env toggle
- [x] #3 Existing findings burned down so the gate lands green on master
- [x] #4 cli/.golangci.yml checked in so local runs match CI
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-14 17:45
---
INVENTORY (operator, 2026-07-14, golangci-lint v2.12.2, no-config, staticcheck+errcheck+ineffassign; nilness unavailable as a standalone enable in this version — the build must wire it via govet's analyzer set): 69 findings total — errcheck 50, staticcheck 11, unused 7 (default-included), ineffassign 1. Concentration: migrate.go 8, invariants/registry.go 7, upgrade/service.go 6, release/check_test.go 6, upgrade/exec.go 5, selfupdate 5, cmd/install.go 5; top-3 files = 30% of total. Log: tmp/lint-inventory-176.log. SIZING VERDICT: a one-session burn-down — errcheck dominates and most hits are likely deliberate best-effort calls needing explicit `_ =` or error handling; the gate can land green quickly once the burn-down unit is dispatched. Queued behind the current arc/fix units.
---

author: foreman
created: 2026-07-14 18:09
---
INVENTORY CORRECTED (mechanic, 2026-07-14): the 69-finding count was SILENTLY TRUNCATED by golangci-lint's own defaults (max-issues-per-linter: 50, max-same-issues: 3 — errcheck's reported 50 was the cap, not the truth). With both caps disabled in cli/.golangci.yml and the cache cleared: 283 findings — errcheck 247, staticcheck 35, ineffassign 1. Concentration: upgrade/service.go 61 (!), upgrade/exec.go 23, migrate/migrate.go 20, invariants/registry.go 14, ~35 files in the tail. Config is DONE and nilness wiring EMPIRICALLY proven (deliberate nil-deref probe caught, then deleted); 'unused' explicitly off (7 residuals out of scope). cert.go batch already burned (7 findings incl. 3 that drifted in today). PLAN: proceed through all 283 in PER-PACKAGE FREEZE BATCHES — mechanical tail first, the three safety-core files (service.go/migrate.go/exec.go) LAST as their own batch with an architect pass; behavior-change candidates (an error that should have been handled) get listed, never silently fixed. The truncation itself is a lesson: the gate's CI job must run with the caps DISABLED, or a red gate could under-report.
---

author: architect
created: 2026-07-14 19:25
---
BATCH-2 SAFETY-CORE PASS (architect, 2026-07-14): SHIP, zero amendments. Bounded-complete scan — all 115 deleted lines decomposed into verified classes, not sampled:
(a) 83 `_ =` explicit-ignores — pure annotation by construction (errcheck flags calls whose error was ALREADY dropped; making the drop explicit changes nothing at runtime). No deleted error-handling anywhere in the diff.
(b) Message-text trims (ST1005 trailing-punctuation class) — text only.
(c) The four logic-bearing style rewrites, each verified: De Morgan's at the pending-above gate is term-by-term exact AND preserves the nil-guard short-circuit order (`flag == nil ||` still protects `flag.Holder`); both QF1003 tagged-switch rewrites are semantically identical (no default = no else existed); the QF1011 `var fetchLog = io.Discard` keeps the identical static type (io.Discard is declared io.Writer in the stdlib) and its Discard default stays load-bearing for the nil-appendLog arm.
(d) ONE genuine behavior addition, benign and correct: the 1KB `io.Copy(io.Discard, io.LimitReader(resp.Body, 1024))` drain before Close (connection-reuse hygiene) — call it out in the commit message as the single non-annotative change.
Also noted approvingly: candidates cataloged in place with concern-comments (e.g. the pruneBackups RemoveAll note) instead of silently fixed — exactly the discipline the ticket asked for.

TOP-3 CANDIDATE SEVERITY (my take, for the candidates ticket): REORDER to #2 > #1 > #3.
- Mechanic's #2 first (pre-restore compose-stop ignored on both restore paths): highest CONSEQUENCE — a silently-failed stop means rsync-restoring the volume UNDER a live postgres, a torn-restored-volume data-corruption pathway. Low likelihood, cheap principled fix (verify-stopped guard before the rsync, fail-fast). Deserves its OWN small ticket, MED.
- Mechanic's #1 second (ABORT-branch restoreDatabase error dropped, service.go:7482): a fail-loud gap in a human-summon path — the progress line claims 'consistent old DB + old code' that a failed restore did not deliver, and support may act on it. No autonomous consumer (services stay down, state=failed). Fix = capture + fold into the ABORT error string. LOW-MED, next wave.
- #3 (CI-not-ready unschedule returns nil regardless): ledger-honesty family, bounded by retry-tick semantics. LOW-MED, rides the family ticket.
None of the three blocks rc.06.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The golangci-lint gate is live and born green. The job runs in go-test.yaml (staticcheck, errcheck, ineffassign; nilness wired via govet's analyzer set — unavailable as a standalone enable in v2.12.2), strict per the ratified doctrine: fails the workflow on any finding, no continue-on-error, caps disabled in cli/.golangci.yml so the gate can never silently under-report (the initial 69-finding inventory was itself cap-truncated — the true count was 283). The burn-down went 283→0 across per-package freeze batches with the three safety-core files reviewed by the architect (batch 2: SHIP, zero amendments — 83 explicit-ignores verified annotation-only, four logic-bearing style rewrites truth-table-verified). Behavior-change candidates were never silently fixed: the fifteen-site catalog spun out as STATBUS-187 (itself fully ruled and shipped). cli/.golangci.yml is checked in so local runs match CI exactly.
<!-- SECTION:FINAL_SUMMARY:END -->
