---
id: STATBUS-203
title: >-
  stale-sb-refresh-guidance: the staleness banner leads with ./sb install on a
  dev box — detect the toolchain and order the suggestions for the machine
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-08-16 14:21'
updated_date: '2026-08-16 18:01'
labels:
  - operator-ux
  - cli
dependencies: []
references:
  - cli/
  - AGENTS.md
priority: low
ordinal: 203000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every operator-facing remedy leads with the right action for THIS machine — the reader pastes the first line and it is correct.
> FOUND: 2026-08-16, the King on his dev box (darwin/arm64, Go toolchain present): the stale-binary banner led with `./sb install` (image-procure + re-exec) and relegated `./dev.sh build-sb` to a parenthetical — backwards for a dev box, and running a local install as the first-line suggestion there is inappropriate. His `./dev.sh build-sb` worked immediately.

THE FIX: the staleness banner detects the environment and orders the remedies accordingly. Detection: a Go toolchain on PATH (exec.LookPath("go")) and/or dev.sh present in the project root → DEV BOX: lead with `./dev.sh build-sb`, mention `./sb install` (image-procure, no toolchain needed) second. Neither present → OPERATOR BOX: lead with `./sb install` exactly as today. The banner's body text otherwise unchanged (built-from/HEAD shas, then re-run guidance).

GROUNDING: the banner is the stale-binary self-recovery surface (the WARN the AGENTS.md dump-discipline note references; emitter near RebuildAndReexec / the staleness check in cli). Mechanic-size: one detection + two orderings; a Go unit pinning both orderings via the detection seam. Same operator-frame lineage as STATBUS-202.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 On a machine with a Go toolchain (or dev.sh present), the staleness banner leads with ./dev.sh build-sb and offers ./sb install second; without one it leads with ./sb install as today
- [ ] #2 A Go unit pins both orderings through the detection seam
- [ ] #3 Proven by observation: one real stale-binary trip on a dev box shows the dev-first ordering
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-16 18:01
---
BUILT + FOREMAN-REVIEWED + COMMITTED e2d5f8952 (2026-08-16; foreman review lane — operator-UX message code, not safety-core or release-gate). The fix lives entirely in cli/internal/freshness/check.go's IsStale (root.go's stalenessGuard just prints its return, so both the hard-fail and WARN paths inherit it): devToolchain detects a development checkout (Go on PATH OR dev.sh present — either signal alone), staleRemedy orders the suggestions for that machine — dev box leads with dev.sh build-sb, operator boxes keep the prior wording byte-unchanged. The detection seam is injected (same pattern as 199's apiBase) so tests pin BOTH orderings deterministically — inside a go-test binary the real PATH always has go, which would otherwise leave the operator branch unexercisable; the mechanic caught that himself and pinned three cases (Go-on-PATH, operator with an asserted-absent dev.sh, dev.sh-alone). Foreman-executed test run: full freshness package GREEN including the pre-existing toolchain-free source-text guard the mechanic hand-traced compatibility against (he replayed the test's line-scan logic with a script, found his first draft would trip it, reworded). SCOPE NOTE accepted as correct: the separate no-reliable-commit-identity banner in root.go is a different failure mode, deliberately untouched. AC#3 (a real dev-box trip showing the new ordering) stays open honestly — the King's next stale-binary encounter proves it for free; ticket stays In Progress on that observation.
---
<!-- COMMENTS:END -->
