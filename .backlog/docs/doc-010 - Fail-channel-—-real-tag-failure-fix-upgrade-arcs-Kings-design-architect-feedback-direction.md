---
id: doc-010
title: >-
  Fail channel — real-tag failure/fix upgrade arcs (King's design, architect
  feedback + direction)
type: specification
created_date: '2026-06-12 05:43'
tags:
  - install-recovery
  - upgrade
  - channels
  - test-fidelity
  - architect-plan
  - product
---
# Fail channel — real-tag failure/fix upgrade arcs

**Origin: the King's design (2026-06-12). Architect feedback + sharpened direction; full design + implementation are a separate King-gated step. Verdict up front: LAND IT — this is the highest-fidelity test shape available to us, and it closes three blind spots the campaign has been circling from different directions.**

## The idea (as dreamt, restated)

A release channel that is neither stable nor prerelease — a **test/fail channel** — backed by a fixture branch that CI builds like any other push. The branch carries a migration with a **fixed, always-latest timestamp** and deliberately failing SQL. The arc: install a baseline from the channel → push the failing migration → wait for images → run the upgrade → **verify it fails and the system survives the failure correctly** (terminal state clean, data intact, no wedge). Failure comes in kinds — the **crash** (erroring migration) and the **wait** (stuck migration). Then a fix-up commit lands → upgrade again → **verify the system completes once the cause is fixed**. The branch is force-pushed so every cycle starts from the same baseline. Possibly one channel per failure kind. Add the commit, test the error scenario; add the commit, test the resolve scenario.

## Why this is right (what it buys that nothing else does)

1. **Zero-scaffolding fidelity.** Every existing failure scenario leans on injection env vars, fabricated upgrade rows, or pre-staged binaries. Each of those rigs has bitten us: pre-staging silently bypassed procurement (doc-006 Part D), fabricated flags drift from the real writer (STATBUS-023), inject env got lost across exec handoffs (STATBUS-013). Here the failure is a **real migration in a real signed commit, built by real CI, discovered by the real channel filter, procured by the real manifest download, applied by the real boot-migrate**. There is no rig to be wrong.
2. **It covers the only production path with zero coverage.** Every real upgrade procures the binary via manifest download (`replaceBinaryOnDisk`); every current scenario short-circuits it. This subsumes and supersedes the proposed tag→tag procurement scenario (doc-007 B5 / King-question #4) — and adds the failure/fix arcs on top.
3. **The fix→retry arc gets its first coverage ever.** We prove failures terminal-state cleanly; we have never proven the *next* upgrade — after the cause is fixed — completes. That arc is the actual operator experience of every real incident, and it is exactly what the unattended-Norway story depends on.
4. **It dissolves the harness's chronic no-delta problem structurally.** Runs 1–7 of the 012 campaign fought procurement/coherence/no-delta layers because scenarios upgrade to HEAD-the-box-is-already-at. Baseline-tag → fail-tag always has a genuine delta by construction.

## The one safety-critical pre-requisite (verified, blocks everything else)

**`FilterTagsByChannel` (cli/internal/upgrade/github.go:456-467) gives the prerelease channel ALL tags** (`return tags // prerelease: all tags`), and discover classifies any hyphenated tag as a prerelease (service.go:2790-2795). Push one `-fail.1` tag today and every prerelease-channel box — dev included — lists a deliberately-failing upgrade as available. **Step zero, before any fail tag exists: make channel filtering exclusive** (stable = no hyphen; prerelease = `-rc.` only; test = `-fail.`/`-stall.` only) with a unit test pinning the exclusivity in both directions. This is a small, standalone, immediately-landable product change.

## Sharpenings to the dream (architect feedback)

1. **Tags, not branch-position, are the upgrade currency — and they never move.** The fixture **branch** is force-pushed freely (authoring surface); the **tags** are immutable and versioned (`-fail.1`, `-fail.2`, … increment per fixture change), preserving the tag-immutability doctrine the product enforces. Tags are also *required* for fidelity: commit/edge procurement builds from source (no Go on real boxes/VMs — the Part-D mechanism), and the edge channel is hardwired to origin/master anyway (github.go:480-485). Tagged releases flow through manifest download — the path we want exercised.
2. **One channel, multiple tag families — not one channel per failure kind.** The channel is box-level config (`UPGRADE_CHANNEL`); the scheduled tag selects the scenario. One `test` channel whose filter admits `-fail.` and `-stall.` families gives one config knob and unlimited scenario freedom (`-fail.N` crash, `-stall.N` wait, future families free).
3. **The cycle as dreamt is the *authoring* flow; the steady-state flow reuses standing fixtures.** Push → wait-for-images → upgrade is how fixtures are *changed*. Once `-fail.N`/`-stall.N`/fix tags exist with built images, the harness scenario consumes them with zero CI wait: install baseline → schedule fail-tag → observe clean failure → schedule fix-tag → observe completion. CI latency is paid once per fixture change, not per test run.
4. **Failure classes and their fix semantics differ — model both:**
   - **Crash** (erroring SQL, never commits): fix = **replace-in-place** — same fixed far-future timestamp (the `2099…` trick the harness already uses for the C12 stall fixture), corrected SQL, next tag. Boot-migrate re-runs it cleanly; nothing recorded from the failed attempt.
   - **Wait/stuck** (SQL that blocks): same replace-in-place model, or released by the fix differently; bounded-behavior assertion is the 012 cover.
   - **The third class the dream unlocks: committed-but-wrong** — a migration that *succeeds* but leaves bad state, repaired by an **append-fix** migration with a later timestamp. No current scenario covers repair-by-follow-up-migration; real incidents look like this.
5. **Production safety beyond the filter:** scheduling a `-fail.` tag should additionally require the test channel to be active (validator refuses the shape on stable/prerelease channels), and supersede/retention logic must be checked so test tags never pollute real channels' rows or the UI of non-test boxes.
6. **Signed fixtures:** discover verifies commit signatures against trusted signers — fixture commits must be signed (author them once; force-push reuses them; CI-authored fixture commits would need a signing identity — prefer human-authored stable fixtures).
7. **This complements the inject layer; it does not replace it.** Real migrations cannot hit micro-windows (the ~ms kill between commit and record, mid-tar kills, flag-phase-specific deaths) — those stay injection-based. Layering: **inject = surgical windows; fail channel = end-to-end arcs.** Both remain.

## Mechanics scope (what the full design must cover — named, not yet designed)

- `FilterTagsByChannel` exclusivity + unit test (step zero, standalone).
- Tag-shape validation across: `./sb upgrade schedule` (accepts the family only on the test channel), discover classification (release_status for test tags), release-tagging tooling (`./sb release` must NOT be the vehicle — fixture tags are authored manually or by a small dedicated helper, never via the release pipeline).
- CI: images for the fixture branch (images.yaml trigger — currently master-push; verify whether tag-push builds suffice) and release assets/manifests for test tags (release.yaml scope — must be verified/extended for the procurement path to find a manifest).
- Harness: one new scenario per arc (fail→rollback→fix→complete; stall→bounded→fix→complete), consuming standing tags; fresh VM per run as today (force-push reset model assumes clean installs).
- Docs: AGENTS.md channel table + the operator-facing channel docs gain the test channel with a do-not-use-in-production warning.

## Where it lands (sequencing)

**Post-gate.** It does not displace the stable-gate critical path (B1 matrix + B2 reds + A1/031 — doc-007). It supersedes B5 in the parallel lanes and becomes the validation track's next structural investment after the gate is green. Exception: **step zero (filter exclusivity) should land with the gate-maker batch** — it is a real latent footgun independent of this feature (any future hyphenated tag shape leaks to prerelease boxes today).

## Open points for the full design

1. Exact tag grammar (`vYYYY.MM.P-fail.N` vs a non-CalVer `test/` prefix — must not collide with CalVer parsers in CompareVersions/validators).
2. Whether the baseline install on the channel is a normal rc tag or a dedicated `-test.base` tag.
3. The committed-but-wrong class: in-scope for v1 or filed as the follow-up family.
4. Opt-in guard shape for non-harness boxes (validator-only vs explicit env ack).
