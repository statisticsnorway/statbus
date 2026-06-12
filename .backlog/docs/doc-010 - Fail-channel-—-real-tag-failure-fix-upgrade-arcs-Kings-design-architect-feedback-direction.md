---
id: doc-010
title: >-
  Fail channel — real-tag failure/fix upgrade arcs (King's design, architect
  feedback + direction)
type: specification
created_date: '2026-06-12 05:43'
updated_date: '2026-06-12 05:54'
tags:
  - install-recovery
  - upgrade
  - channels
  - test-fidelity
  - architect-plan
  - product
---
# Fail channel — branch-as-channel failure/fix upgrade arcs

**Origin: the King's design (2026-06-12). CORRECTED 2026-06-12 after the King's review: the first draft modeled the channel as a series of immutable tags — a category error. A channel is a MUTABLE pointer (its identity is "what it points at now"); tags name fixed things, branches name changing states. The repo already settles the vehicle: the entire deploy architecture is branches-as-pointers (`ops/*/deploy/*`, force-pushed per deploy). The fail channel is one more branch-as-pointer. This revision rebuilds the direction on branches; the doc-009 port +6 design is unaffected (King-affirmed).**

## The idea (the King's, restated)

A release channel that is neither stable nor prerelease — backed by a **branch** that CI builds on push, like the deploy branches. The branch carries a migration with a **fixed, always-latest timestamp** and deliberately failing SQL. The arc: install from the branch baseline → push the failing migration (branch pointer moves) → wait for images → run the upgrade → **verify it fails and the system survives correctly** (clean terminal state, data intact, no wedge). Failure kinds: the **crash** (erroring migration) and the **wait** (stuck migration) — possibly one branch/channel per kind (`channel/fail`, `channel/stuck`). Then the fix-up commit lands (pointer moves again) → upgrade → **verify it completes once the cause is fixed**. The branch is force-pushed back to baseline for the next cycle. Add the commit, test the error scenario; add the commit, test the resolve scenario.

## Why this is right (unchanged in substance)

1. **Zero-scaffolding fidelity.** The failure is a real migration in a real signed commit, built by real CI, discovered by the real channel logic, applied by the real boot-migrate. No inject env (013's loss class), no fabricated rows (023's drift class), no pre-staged binaries (Part-D's vacuity class). There is no rig to be wrong.
2. **The fix→retry arc gets its first coverage ever** — we prove failures land cleanly; we have never proven the *next* upgrade completes once the cause is fixed. That arc is the operator experience of every real incident and the substance of the unattended-Norway story.
3. **It structurally dissolves the harness's chronic no-delta problem** — baseline-commit → fail-commit always has a genuine migration delta by construction (the 012 campaign burned multiple runs on exactly this).
4. **Channels-as-branches matches production reality** — SSB cloud deploys ARE branch-pointer upgrades already; testing that shape tests what production does.

## The vehicle: branches as channels

- **Channel = branch.** `UPGRADE_CHANNEL` resolves to a branch ref for commit discovery. Product change: `DiscoverCommitsViaGit` is hardcoded to `origin/master` (github.go:480-485) — generalize it to follow the channel's branch. The existing `edge` channel becomes the special case (edge = master); the test families are siblings (`channel/fail`, `channel/stuck`). One branch per failure family, per the King's original instinct — under the branch model channels are cheap, and the box's channel config selects the family.
- **The oscillating pointer is the steady state.** The fixture commits are PREPARED, signed, and stable; a test cycle force-pushes the branch **between existing commits** (base → fail-commit → fix-commit → base). Commit SHAs don't change → the commit-addressed images (ghcr tags are already commit identities) stay built → **zero CI wait per test run**. CI cost is paid only when a fixture commit itself changes. (This is strictly better than the abandoned tag-series model, which minted permanent artifacts per cycle.)
- **Fixed-latest-timestamp migrations carry the failure** (the far-future-timestamp trick the harness's C12 fixture already uses): crash fix = replace-in-place (same timestamp, corrected SQL, next commit); stall fix = same; and the model also unlocks the **committed-but-wrong + append-fix** class (a migration that succeeds but leaves bad state, repaired by a later migration) — no current scenario covers repair-by-follow-up, and real incidents look like that.

## The one surviving engineering requirement: commit-addressed binary procurement

Verified at the line level: tagged releases procure via **tag-addressed manifest download** — `replaceBinaryOnDisk` → `FetchManifest(version)` (service.go:5040-5057). Branch commits have "no release artifact in any GitHub manifest" (the code's own comment, :5060-5062) → `buildBinaryOnDisk` runs `make -C cli build` **on the box** (:5059+). The harness VMs have no Go **by design** (the fidelity choice that exposed Part D), and external standalone boxes never will.

So the fail channel needs **commit-addressed binary delivery**: CI already builds the `sb` binary per push (images workflow / the harness's build step) and already publishes commit-addressed Docker images to ghcr — the gap is publishing the **binary** commit-addressed and teaching commit-target procurement to try download-before-build. Rejected alternatives: Go on the test VMs (breaks the no-Go fidelity that caught Part D), pre-staging the binary (IS the Part-D vacuity pattern).

**Bonus this unlocks beyond the test channel:** SSB cloud deploys are branch-commit upgrades that today build on-box (Go required on hosts). Commit-addressed download-procurement lets cloud and standalone converge on the same procurement path — one less host dependency, and the external-standalone story strengthens. The fail channel's requirement is a product improvement in its own right.

## What survives from the first draft (vehicle-independent)

- **STATBUS-033 — channel exclusivity** stands on its own merits, independent of this feature: `FilterTagsByChannel` (github.go:456-467) gives the prerelease channel ALL tags — any future hyphenated tag shape is one UI click from installing on dev today. With branches-as-channels there are no test tags, so 033 is not a blocker for this feature — it is simply a real latent footgun to fix in the gate batch. The same exclusivity principle extends to the channel→branch mapping (a box on `channel/fail` must discover ONLY that branch; a box on stable must never see branch-commit candidates).
- **Signed fixtures** — discover verifies commit signatures against trusted signers; the prepared fixture commits must carry trusted signatures (author + sign once; the oscillating pointer reuses them).
- **Opt-in guard** — a box whose channel is a test family should require an explicit acknowledgment (config-level), so a mis-set channel on a real box refuses rather than installs a deliberate failure.
- **Layering** — complements the inject scenarios, does not replace them: real migrations cannot hit micro-windows (the ~ms commit↔record kill, mid-tar kills). Inject = surgical windows; fail channel = end-to-end arcs.

## What dies with the tag model

Tag grammar, test-tag immutability/versioning, `-fail.N` pollution concerns, release.yaml asset scope for test tags — all artifacts of the wrong vehicle. Gone.

## Mechanics scope (for the full design)

- Channel→branch mapping in config + `DiscoverCommitsViaGit` generalization (github.go:480-485) + channel-exclusive discovery.
- Commit-addressed binary artifact: where it lives (ghcr OCI artifact vs commit-named release asset vs other), retention, SHA256 verification in procurement (mirror `selfupdate.ReplaceBinaryOnDisk`'s checksum contract), download-before-build ordering in commit-target procurement.
- CI: images workflow trigger for the fixture branches (currently master-push); binary publish step.
- Fixture branches + prepared signed commits (base / fail / fix per family); authoring runbook (how to change a fixture = new signed commits + rebuild, then pointer oscillation resumes).
- Harness: one scenario per arc consuming the standing branches (install base → re-point → upgrade → assert clean failure → re-point → upgrade → assert completion); fresh VM per run as today.
- Supersede/retention hygiene: branch-commit candidate rows must not pollute real channels' rows/UI.
- Docs: AGENTS.md channel table + operator docs (test families marked do-not-use-in-production).

## Sequencing

**Post-gate** (does not displace B1/B2/A1 on the doc-007 critical path). STATBUS-033 rides the gate-maker batch on its own merits. The commit-addressed-procurement piece can be designed in parallel with the gate work since it touches procurement code the gate work doesn't.

## Open points for the full design

1. Commit-addressed artifact store choice (ghcr OCI artifact vs commit-named GitHub asset vs other) + retention policy.
2. Channel→branch mapping shape in `.env.config` (explicit branch ref vs naming convention `channel/<family>`).
3. Baseline commit identity: the fixture branch's base should track a real release (the rc's commit) or a pinned older baseline — pick at design time.
4. Guard shape for non-test boxes (config ack vs validator refusal vs both).
5. Whether the committed-but-wrong + append-fix family is v1 or the first follow-up.
