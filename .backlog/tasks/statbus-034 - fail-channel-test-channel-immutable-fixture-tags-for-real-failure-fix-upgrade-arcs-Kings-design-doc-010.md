---
id: STATBUS-034
title: >-
  fail-channel: branches-as-channels for real failure/fix upgrade arcs (King's
  design)
status: To Do
assignee: []
created_date: '2026-06-12 05:44'
updated_date: '2026-06-12 08:01'
labels:
  - install-recovery
  - upgrade
  - channels
  - test-fidelity
  - product
  - needs-king-ratification
dependencies:
  - STATBUS-033
references:
  - cli/internal/upgrade/github.go
  - cli/internal/upgrade/service.go
  - test/install-recovery/README.md
  - .github/workflows/images.yaml
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: real failure→fix upgrade arcs through the box's own discovery/procurement — branches as channels, zero test scaffolding.
> BENEFIT: two concrete gains — (1) the box's DISCOVERY path (how Norway actually receives upgrades: channel → discover → procure) gets its first arc coverage, complementing 071's operator-push arcs; (2) commit-addressed binary download frees every box (and cloud deploys) from needing Go on the host — one converged procurement path.
> STAGE: post-gate Testing foundation → Stage 3.
> COMPLEXITY: architect-design first (AC#7 ratification of the open points), then engineer-substantial (procurement + CI + fixture branches).
> DEPENDS ON: nothing open (its recorded dependency STATBUS-033 shipped); gated on the King's AC#7 ratification, which is a decision, not a ticket.

---

THE KING'S DESIGN (2026-06-12): test-family release channels backed by BRANCHES (channels are mutable pointers; branches are git's mutable pointer — the same primitive as the ops/*/deploy/* deploy branches). E.g. channel/fail (crash kind) and channel/stuck (wait kind). Each branch carries prepared, SIGNED fixture commits: base → a migration with a fixed always-latest timestamp and deliberately failing/stalling SQL → the fix-up commit. A test cycle oscillates the branch pointer between EXISTING commits (force-push base→fail→fix→base): SHAs stable → commit-addressed images stay built → ZERO CI wait per run; CI cost only when a fixture commit itself changes.

WHAT IT BUYS (nothing else covers these): the full production loop with zero test scaffolding — real discovery → real procurement → real boot-migrate delta → real failure → clean terminal state → pointer to fix → re-upgrade COMPLETES. First-ever coverage of the fix→retry arc (the actual operator incident experience); dissolves the harness's chronic no-delta problem (baseline→fail always has a real delta); matches production reality (SSB cloud deploys ARE branch-pointer upgrades).

THE ONE ENGINEERING REQUIREMENT (verified): commit-target procurement today is build-on-box (buildBinaryOnDisk service.go:5059+ — "no release artifact exists for edge commits"; manifest download :5040 is tag-addressed) and test VMs / external boxes have no Go by design → CI must publish the sb binary COMMIT-ADDRESSED and commit-target procurement learns download-before-build (SHA256-verified). Bonus: frees cloud deploys from the Go-on-host dependency — cloud and standalone converge on one procurement path.

SCOPE: channel→branch mapping in config + DiscoverCommitsViaGit generalization (hardcoded origin/master, github.go:480-485) + channel-exclusive discovery; commit-addressed artifact store + verified download; CI triggers for fixture branches; prepared signed fixture commits + authoring runbook; 2 harness arc scenarios; supersede/retention hygiene; opt-in guard for non-test boxes; AGENTS.md + operator docs.

SEQUENCING: post-gate (does not displace the stable-gate batch). STATBUS-033 (channel exclusivity) is related-but-independent and rides the gate batch. King ratifies the full design (AC#7) before implementation; the open design points are listed in Implementation Notes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Commit-addressed binary procurement: CI publishes the sb binary per commit; commit-target procurement downloads (SHA256-verified) before falling back to build
- [ ] #2 Fixture branches exist with prepared signed commits (base / fail / fix per family) and built images; authoring runbook documented
- [ ] #3 Harness scenario, fail arc: install base → pointer to fail-commit → real discovery+procurement+upgrade → clean rollback/terminal + data intact → pointer to fix-commit → upgrade COMPLETES
- [ ] #4 Harness scenario, stall arc: same flow, stuck migration bounded by the watchdog/timeout covers, fix completes
- [ ] #5 Channel exclusivity: a box on a test-family branch discovers ONLY that branch; stable/prerelease boxes never see branch-commit candidates (unit + discover-level checks)
- [ ] #6 Channel + fixture workflow documented (AGENTS.md table, operator docs with do-not-use-in-production warning)
- [ ] #7 Full design ratified by the King: channel→branch mapping shape, commit-addressed artifact store + retention, fixture-branch baseline choice, guard shape (the open points listed in Implementation Notes)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DESIGN RATIONALE + ALTERNATIVES (consolidated here per the plans-live-in-tickets convention; doc-010 is stubbed to this ticket).

VEHICLE — branches, not tags (King correction 2026-06-12): a channel's identity is "what it points at now" — mutable by definition. The architect's v1 modeled it as immutable versioned tags (-fail.1, -fail.2, …) — rejected: permanent artifacts minted per cycle to simulate pointer moves, plus latest-of-series enumeration reimplementing branch semantics badly. The branch model is also strictly better on CI cost (pointer oscillation between stable SHAs invalidates nothing).

WHY ZERO-SCAFFOLDING FIDELITY (the three rig classes that bit us): pre-staged binaries silently bypassed procurement (doc-006 Part-D vacuity); hand-fabricated flags/rows drift from the real writers (023); inject env was lost across the inline exec handoff (013). A real signed commit on a real branch built by real CI has no rig to be wrong.

PROCUREMENT — rejected alternatives for the no-Go-on-box problem: Go on the test VMs (destroys the no-Go fidelity that exposed Part D); pre-staging the binary (IS the Part-D pattern); keep build-on-box (excludes exactly the boxes the channel must serve — and external standalone forever). Hence commit-addressed download-before-build, checksum-verified mirroring selfupdate.ReplaceBinaryOnDisk's contract.

LAYERING: complements the inject scenarios, does not replace them — real migrations cannot hit micro-windows (the ~ms commit↔record kill, mid-tar kills). Inject = surgical windows; fail channel = end-to-end arcs (fail→rollback→fix→complete; stall→bounded→fix→complete; future family: committed-but-wrong→append-fix — a migration that SUCCEEDS but leaves bad state, repaired by a later migration; no current scenario covers repair-by-follow-up).

OPEN POINTS to resolve at ratification (AC#7): (1) commit-addressed artifact store (ghcr OCI artifact vs commit-named asset vs other) + retention policy; (2) channel→branch mapping shape in .env.config (explicit ref vs channel/<family> naming convention); (3) fixture-branch baseline identity (track an rc commit vs pinned older baseline); (4) guard shape for non-test boxes (config ack vs validator refusal vs both); (5) committed-but-wrong family in v1 or first follow-up.
<!-- SECTION:NOTES:END -->
