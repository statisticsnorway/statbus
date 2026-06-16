---
id: STATBUS-065
title: >-
  selfheal-toolchain-free: ./sb install staleness self-heal shells `make` →
  fails (127) on toolchain-less hosts → operator can't recover a post-swap crash
status: To Do
assignee: []
created_date: '2026-06-16 12:02'
labels:
  - upgrade
  - recovery
  - install
  - robustness
  - north-star
  - architect-plan
dependencies: []
priority: high
ordinal: 65000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PRODUCTION-RELIABILITY GAP surfaced by the install-recovery harness (2-preswap-checkout-kill (a), CI run 27614658333). North-Star-critical (STATBUS-039: the operator's one recovery action must work on the actual deployment hosts, which have NO Go toolchain).

## Mechanism (foreman-verified, file:line)
- cli/cmd/root.go:62 `PersistentPreRun: stalenessGuard`. root.go:112 `freshness.IsStale(ProjectDir, commitSHA)`; root.go:124 if the command is annotated `selfheal=true` (e.g. `./sb install`) and stale → `freshness.RebuildAndReexec(ProjectDir)`.
- cli/internal/freshness/rebuild.go:19/37 — RebuildAndReexec runs `exec.Command("make", "-C", "cli", "build")`.
- On a host with NO Go/make toolchain (production deployments) → `make build` exits 127 → "Self-heal rebuild/exec failed: rebuild failed: exit status 2" → the command ABORTS. The staleness model assumes a DEV host (check.go:195 suggests `./dev.sh build-sb`).

## Reachability (architect to map fully)
A post-swap-crash recovery has binary=NEW (image-extracted + swapped) while tree=OLD (checkout deferred, STATBUS-060). The operator's canonical recovery `./sb install` (selfheal=true) → stalenessGuard → STALE → `make` → 127 → CANNOT RECOVER on a toolchain-less host.
- BOUNDED: 0-happy-upgrade is GREEN on the toolchain-less VM, and it recovers via the systemd `./sb upgrade service` daemon — so the DAEMON path does NOT trip this. The gap is specifically the operator `./sb install` path (confirm).

## Fix direction (architect design; run by King before code)
Make the self-heal TOOLCHAIN-FREE: re-procure the binary via image-extract (mirror 09ac1f7e4 procureSbFromImage: `docker create statbus-sb:<short>` + `docker cp`), NOT `make`. OR: do not treat the legitimate binary-ahead-of-tree recovery state as "stale-needs-rebuild" (checkout the tree to match the binary first, then proceed). Keep the dev-host `make`/`./dev.sh build-sb` path for dev iteration.

## Why it gates rc.04
- It's why (a) 2-preswap-checkout-kill dies (before recovery) → rc.04's from_commit_sha PRIMARY path is unvalidated.
- It will also break STATBUS-060's real-install.sh recovery (install.sh runs `./sb install` → trips this on a toolchain-less VM).
OWNER: architect. Aligns with STATBUS-039 + the toolchain-free design (09ac1f7e4).
<!-- SECTION:DESCRIPTION:END -->
