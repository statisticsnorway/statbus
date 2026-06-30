---
id: doc-020
title: Controlled-B upgrade-test target — replace HEAD in install-recovery scenarios
type: specification
created_date: '2026-06-30 14:48'
tags:
  - upgrade
  - install-recovery
  - testing
  - controlled-B
  - architecture
  - STATBUS-071
---
# Controlled-B upgrade-test target (replace HEAD)

**Status:** design, awaiting King's ratification. Architect, 2026-06-30. Foundation, not patch.
**Problem origin:** King's diagnosis — install-recovery *scenarios* upgrade to `HEAD`, which is
wrong. The *arcs* already use a controlled target B; unify the scenarios onto that model.

## Context — two harnesses, two target models (all verified first-hand)

`test/install-recovery/` has two harnesses testing overlapping upgrade/recovery wedges:

**SCENARIOS** (`scenarios/*.sh`, dispatcher `run.sh`) — upgrade `<old-release-tag>` → **HEAD**:
- `HEAD_SHA=$(git -C "$HARNESS_ROOT" rev-parse HEAD)` (e.g. `3-postswap-mid-tx-kill.sh:74`).
- HEAD has no per-commit ghcr image, so `fixtures/stage-head.sh` **retags** the installed
  release's 4 images as HEAD's `COMMIT_SHORT` → `docker compose pull` falls back to local. Only
  the **migration delta** (git-tree SQL applied by the swapped `./sb`) is genuinely HEAD's.
- A real delta is *forced* via `SB_INSTALL_SKIP_SEED=1` (`lib/vm-bootstrap.sh:464-480`).
- **Locally orchestratable** (`./dev.sh test-install-recovery <slug>` from a dev laptop; the retag
  means the target needs no CI image build — only the base release images on ghcr).

**Three failure modes (King's diagnosis, all grounded):**
1. **HEAD moves** — a doc-only commit advances HEAD, adds no migration → baseline==HEAD → assert
   `✗ no real migration delta … SB_INSTALL_SKIP_SEED did not withhold the seed` (`3-postswap-mid-tx-kill.sh:138`).
2. **HEAD unpushed** — `stage-head.sh:38` `git fetch --depth 1 origin "$HEAD_SHA"` → `FATAL: HEAD not on origin`.
3. **Uncontrolled delta** — `<tag>→HEAD` is an arbitrary migration range; a kill-mid-migration test
   needs a *specific, known* migration to interrupt deterministically.

The 9 current matrix failures are all the kill-during-`old→HEAD` scenarios.

**ARCS** (`arcs/*.sh`, `lib/arc-helpers.sh`, CI `.github/workflows/upgrade-arc-harness.yaml`) —
already use a controlled, pushed, known-delta **B**:
- `construct` job `build_pair` (`upgrade-arc-harness.yaml:199-244`): `git checkout -B <b_branch>
  <base_sha>` → write a **synthetic migration** (`write_working_v` creates `public.upgrade_arc_fixture`;
  `write_failing_v` is a deterministic `RAISE EXCEPTION` = V_fail) → `git commit -S` (ephemeral-key
  signed) → push to origin (`:248-252`). `V_VERSION = max(A's migration timestamps)+1` (`:135`),
  sorting after every A migration; `V_VERSION_2 = +2`.
- **Only two lineages cover every arc** (`:240-244`): `build_pair working …` + `build_pair failing
  …`. "kill/stall arcs ride working; failing/rollback arcs ride failing." → controlled-B is *shared*,
  not per-scenario.
- Each branch dispatches `images.yaml` → **real per-commit images** `statbus-*:<short>` on ghcr
  (`:262+`); an image-wait job polls until all exist. **CI-only** (B is not available before the run).
- `arc_to()` (`arc-helpers.sh:95`): `git fetch origin $B_BRANCH && git cat-file -e $B_FULL` →
  `./sb upgrade register` → `wait_for_upgrade_candidate_ready` → `./sb upgrade schedule` → poll
  `public.upgrade` terminal. Kill variants: `arc_schedule_daemon_down` + `arc_install_dispatch_with_inject`.

**The arc↔scenario filename lists are ~1:1** (preswap-backup-kill, postswap-mid-tx-kill,
between-migrations-kill, rollback-kill, …). Same wedges; they differ only in target model
(controlled-B vs HEAD), image strategy (real build vs retag), and dispatch (service vs inline-install).

## Key insight — retag is sound for a controlled-B scenario

Every recovery wedge interrupts a **backup / git-checkout / binary-swap / migration / rollback** —
none of which exercises app/worker/db/proxy **container code** (the db container is the same
Postgres in A and B; the migration is git-tree SQL applied by the swapped binary). So a scenario's
container images need only be *present*, not *be B's real build*. Retagging A's images as B's
`COMMIT_SHORT` is therefore correct, and B's controlled migration still applies from B's git
checkout — exactly as HEAD's delta does today. The retag was never the bug; the **moving, unpushed,
uncontrolled HEAD** was.

## Recommended approach (X) — share the B-branch constructor; keep the scenario retag tail

**Lift the arc's B-*branch* construction into one shared primitive; give the scenarios a controlled
B instead of HEAD; keep their retag image tail (so they stay fast + locally orchestratable).**

1. **Shared primitive** `lib/upgrade-target.sh :: construct_upgrade_target BASE_SHA <spec>` —
   exports `B_FULL, B_BRANCH, V_VERSION[, V_VERSION_2]`. It is the existing `build_pair` +
   `write_working_v` / `write_failing_v` logic lifted **out of the workflow YAML into a script**
   callable from both CI and a local run: branch off `BASE_SHA`, write the synthetic migration(s),
   sign (ephemeral key, trusted post-install via the existing `trust_arc_signer`), push to origin.
   `<spec>` is a small enum of *known* deltas, each a fixture migration the harness owns:
   `working` (1 migration → `upgrade_arc_fixture`), `working-2` (two; forward-recovery
   `max_version==V_VERSION_2`), `failing` (V_fail), `slow` (sleeps past the watchdog — migration-timeout).
   The arc `images.yaml` build and the scenario retag are **pluggable tails** on the same B.
2. **Construct the canonical Bs once per run, share across the matrix** (mirrors the arc's two-lineage
   design). A scenario picks the B it needs by env (`B_FULL/B_BRANCH/V_VERSION`); the construct step
   is git-only (cheap) for the scenario tier — no image build.
3. **Scenarios consume B, not HEAD.** Replace each upgrade scenario's `HEAD_SHA=…rev-parse HEAD` +
   `SB_INSTALL_SKIP_SEED=1` + `stage-head.sh` with: install A (`BASE_SHA`) → consume the shared B →
   `git fetch origin $B_BRANCH` → upgrade A→B (inline `./sb install` dispatch) with the same
   `STATBUS_INJECT_AT` wedge. `stage-head.sh` generalizes to `stage-target.sh <B_SHA>` (retag onto
   B's short SHA). The interrupted migration is now the *known* fixture migration → deterministic.
4. **Pure install-state tests stay on HEAD / this-commit** (the King's happy-install exception,
   generalized). Dividing principle:
   > **Interrupts/depends on a specific MIGRATION or an A→B UPGRADE → controlled-B.
   > Only exercises the installer's handling of an install-state on this commit → HEAD.**
   So `0-happy-install`, the `5-install-*` installer-state tests, and the non-upgrade `1-boot-*`
   keep HEAD; `0-happy-upgrade` becomes a working-B run (≡ `working-arc.sh`).

**Branch naming / lifecycle** — align to the existing arc convention, scenario variant:
`test/upgrade-target/<run-id>/<spec>` (force-push to origin; the COMMIT `B_FULL` is authoritative,
the branch is only the fetch handle). Created at run start, `git push origin --delete` at run end;
a GC sweep removes orphaned `test/upgrade-target/*` and `test/upgrade-arc-*` branches older than N days.

**Tradeoff, stated:** X keeps two tiers — scenarios (controlled-B + retag: fast, locally
orchestratable, recovery-wedge-focused) and arcs (controlled-B + real images: CI-only, full-fidelity,
autonomous-service-focused) — sharing one B-branch constructor. I'd ship X: it directly satisfies
"a branch, not HEAD," fixes all three failure modes, preserves the fast local loop, and is the
smaller change.

## Strategic alternative (Y) — for the King to weigh, not my default

The ~1:1 arc↔scenario overlap means the kill/stall scenarios are nearly the kill/stall arcs with a
different target+dispatch. **Y = collapse to one harness**: delete the scenario wedges, let the
arcs' controlled-B real-image cases cover them, keep only the genuinely install-only tests
(`5-install-*`, non-upgrade `1-boot-*`) as HEAD-install tests. Y is simpler and higher-fidelity but
**loses the fast locally-orchestratable tier** (everything becomes CI-built-image, ~20-30 min image
waits) and is a large deletion. Recommend Y only if the King prioritizes one-harness simplicity over
local iteration speed. **This is the one strategic call I need from the King.**

## Critical files
- `test/install-recovery/fixtures/stage-head.sh` — retag; generalize to `stage-target.sh <B_SHA>`.
- `test/install-recovery/run.sh:239` — `rev-parse HEAD` stamp; add the cheap git-only B-construct step.
- `test/install-recovery/lib/arc-helpers.sh:95/267/294` — the B-consumption flow (already shared).
- `test/install-recovery/lib/vm-bootstrap.sh:464-480` — `SB_INSTALL_SKIP_SEED` (retired for B scenarios).
- `.github/workflows/upgrade-arc-harness.yaml:130-260` — `build_pair`/`write_working_v`/`write_failing_v`/
  `V_VERSION` — **lift this into `lib/upgrade-target.sh`** as the shared constructor.
- The ~13 `scenarios/*.sh` with `HEAD_SHA=$(… rev-parse HEAD)` (grep-captured) — migrate the upgrade ones.

## Verification (the real VM is the only oracle — doc/install-upgrade-testing.md)
- A doc-only commit on HEAD no longer breaks any upgrade scenario (B is independent of HEAD).
- An unpushed local HEAD no longer breaks a scenario (B is pushed; A is a pinned release/commit).
- `3-postswap-mid-tx-kill` interrupts the known fixture migration deterministically — no SKIP_SEED,
  no `no real migration delta` assert.
- `./dev.sh test-install-recovery <slug>` (local) + CI matrix `install-recovery-harness.yaml`.

## Open questions for the King
1. **X vs Y** — share-constructor-keep-two-tiers (recommended) vs collapse-to-one-CI-harness.
2. **Scope of pass 1** — foundation = the shared `construct_upgrade_target` + migrate the ~13
   upgrade/delta scenarios off HEAD. The arc↔scenario dedup is a flagged follow-up regardless of X/Y.
