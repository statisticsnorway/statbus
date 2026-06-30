---
id: doc-020
title: Controlled-B upgrade-test target — replace HEAD in install-recovery scenarios
type: specification
created_date: '2026-06-30 14:48'
updated_date: '2026-06-30 14:55'
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
**Now grounded:** the 9 current matrix failures are this exact issue — diagnosed by the engineer,
verified by the foreman, re-verified first-hand by the architect against the CI logs (below).

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
   `✗ no real migration delta …` (`3-postswap-mid-tx-kill.sh:138`).
2. **HEAD unpushed** — `stage-head.sh:38` `git fetch --depth 1 origin "$HEAD_SHA"` → `FATAL: HEAD not on origin`.
3. **Uncontrolled delta** — `<tag>→HEAD` is an arbitrary migration range; a kill-mid-migration test
   needs a *specific, known* migration to interrupt deterministically.

**ARCS** (`arcs/*.sh`, `lib/arc-helpers.sh`, CI `.github/workflows/upgrade-arc-harness.yaml`) —
already use a controlled, pushed, known-delta **B**:
- `construct` job `build_pair` (`upgrade-arc-harness.yaml:199-244`): `git checkout -B <b_branch>
  <base_sha>` → write a **synthetic migration** (`write_working_v` creates `public.upgrade_arc_fixture`;
  `write_failing_v` is a deterministic `RAISE EXCEPTION` = V_fail) → `git commit -S` (ephemeral-key
  signed) → push to origin (`:248-252`). `V_VERSION = max(A's migration timestamps)+1` (`:135`).
- **Only two lineages cover every arc** (`:240-244`): `build_pair working …` + `build_pair failing
  …`. → controlled-B is *shared*, not per-scenario.
- Each branch dispatches `images.yaml` → **real per-commit images** `statbus-*:<short>` on ghcr; an
  image-wait job polls until all exist. **CI-only** (B is not available before the run).
- **Trusts the synthetic-commit signer** post-install via `trust_arc_signer` (`arc-helpers.sh:24`)
  — the scenarios have no equivalent (see failure mode 3 in the diagnosis).
- `arc_to()` (`arc-helpers.sh:95`): `git fetch origin $B_BRANCH && git cat-file -e $B_FULL` →
  `./sb upgrade register` → `wait_for_upgrade_candidate_ready` → `./sb upgrade schedule` → poll.

**The arc↔scenario filename lists are ~1:1** — same wedges; they differ only in target model
(controlled-B vs HEAD), image strategy (real build vs retag), and dispatch (service vs inline-install).

## Diagnosis — the 9 matrix failures (engineer obs #1332, architect re-verified vs CI run 28444189604)

**Verdict: NOT a code regression** (zero backup/`pg_dump`/`dbdump`/`archiveBackup` in any failure
path; if our code had regressed we'd see consistent upgrade-row/rollback corruption — instead it's
**three distinct harness gates**, which is decisive). It is exactly the HEAD-target / multi-commit
**incoherence** this design fixes.

**The incoherent baseline (the crux):** the VM is provisioned with seed + git-HEAD at **`50fd4325`**
("seed-sync-and-pin-gate", ~1047 commits back) while the upgrade target + uploaded `sb` binary =
the run's commit **`18734a422`**. So image-tag, git-checkout, upgrade-target, and seed are spread
across **two** commits. Every recovery install warns (verified `4-rollback-kill.log:3877`):
`WARN: ./sb is stale: built from 18734a42, HEAD is now 50fd4325 with cli/ changes.`

**Why only the kill-recovery scenarios fail** (16 pass, incl. `0-happy-upgrade`, all `1-boot`, all
`5-install`): only the kill scenarios run a **second** `./sb install` (the recovery), which trips
three gates the happy/install paths never reach:

1. **Self-heal procure fail** (`4-rollback-kill.log:4126-4135`): the staleness guard tries to
   procure `sb` for the git HEAD → `Pulling … statbus-sb:50fd4325 … not found` → local fallback
   `building locally via cli/Dockerfile.sb` → `ERROR: open Dockerfile.sb: no such file or directory`
   → `Self-heal procure/exec failed`. (No image for the seed-pin commit; the local build is run
   from the wrong dir / missing file.)
2. **Mandatory signature verify, no signers** (`3-postswap-mid-tx-kill.log:5482`):
   `Commit 18734a42 signature verification failed: no trusted signers configured — signature
   verification is mandatory.` The harness VM configures no `UPGRADE_TRUSTED_SIGNER_*`. (Note the
   row: `has_migrations: false` — the doc-only target had no delta, failure mode 1, too.)
3. **DB-sessions gate vs the live worker** (`mid-migration-kill.log:5290`): `[10/16] Database
   sessions FAILED: connection pool still saturated after cleanOrphanSessions`. **Crucially the
   recovery itself SUCCEEDED** — `:5265` `State after recovery: nothing-scheduled` — and `:5294`
   the failure is an `INVARIANT FAILED_INSTALL_HAS_AUDIT_TRAIL violated (audit-only)` on a
   **subsequent verification install** tripping on the worker (PID 328) actively running the
   post-recovery derive pipeline. A *verification* gate, not a recovery failure.

## Key insight — retag is sound for a controlled-B scenario

Every recovery wedge interrupts a **backup / git-checkout / binary-swap / migration / rollback** —
none of which exercises app/worker/db/proxy **container code** (the db container is the same
Postgres in A and B; the migration is git-tree SQL applied by the swapped binary). So a scenario's
container images need only be *present*, not *be B's real build*. Retagging A's images as B's
`COMMIT_SHORT` is therefore correct, and B's controlled migration applies from B's git checkout. The
retag was never the bug; the **moving, unpushed, uncontrolled, incoherent HEAD** was.

**Verified (2026-06-30) — and it bears directly on the X/Y call:** at *upgrade* time migrations are
applied from the **git working tree**, not from any image (`cli/internal/migrate` runs psql with
`cmd.Dir=projDir`; no `go:embed`; `postgres/Dockerfile:466/536` bake migrations+seed only for *seed
creation*, never re-run on an existing volume). The db/sb/app image builds `COPY` the whole repo
(`Dockerfile.sb:35`, `app/Dockerfile:25`), so a new migration file busts their cache and they
rebuild — but the rebuilt images are **functionally identical** to A's (no runtime code changed;
worker/proxy even cache-hit). So for a migration-only target — which is *every* recovery wedge —
building real images (Y) buys **determinism / one-harness uniformity, but not container fidelity**;
the migration runs from git either way (this is also *why* today's retag works at all). Real images
earn their keep only when a target changes container **code** (Go/TS/Caddy), which no recovery wedge
does. The branch-build mechanics are identical whether images are built or retagged — so that is a
**speed knob, independent of the branch design**.

## Recommended approach (X) — share the B-branch constructor; keep the scenario retag tail

**Lift the arc's B-*branch* construction into one shared primitive; give the scenarios a coherent,
pinned A and a controlled B instead of HEAD; keep their retag image tail (so they stay fast +
locally orchestratable).**

1. **Shared primitive** `lib/upgrade-target.sh :: construct_upgrade_target BASE_SHA <spec>` —
   exports `B_FULL, B_BRANCH, V_VERSION[, V_VERSION_2]`. It is the existing `build_pair` +
   `write_working_v` / `write_failing_v` logic lifted **out of the workflow YAML into a script**
   callable from both CI and a local run: branch off `BASE_SHA`, write the synthetic migration(s),
   sign (ephemeral key), push to origin. `<spec>` ∈ {`working`, `working-2`, `failing` (V_fail),
   `slow` (sleeps past the watchdog)} — the same fixtures the arcs own. Image build (arc) vs retag
   (scenario) is a **pluggable tail** on the same B.
2. **Construct the canonical Bs once per run, share across the matrix** (mirrors the arc's
   two-lineage design); a scenario picks its B by env. Construct is git-only (cheap) for scenarios.
3. **Scenarios consume B, not HEAD.** Replace each upgrade scenario's `HEAD_SHA` + `SB_INSTALL_SKIP_SEED`
   + `stage-head.sh` with: install A (`BASE_SHA`) → consume the shared B → `git fetch origin
   $B_BRANCH` → upgrade A→B (inline `./sb install` dispatch) with the same `STATBUS_INJECT_AT` wedge.
   `stage-head.sh` generalizes to `stage-target.sh <B_SHA>`. The interrupted migration is the *known*
   fixture migration → deterministic.
4. **Pure install-state tests stay on HEAD / this-commit** (the King's happy-install exception).
   Dividing principle:
   > **Interrupts/depends on a specific MIGRATION or an A→B UPGRADE → controlled-B.
   > Only exercises the installer's handling of an install-state on this commit → HEAD.**
   `0-happy-install`, the `5-install-*`, and non-upgrade `1-boot-*` keep HEAD; `0-happy-upgrade`
   becomes a working-B run (≡ `working-arc.sh`).

### Three requirements the diagnosis adds (apply under both X and Y)

- **(a) COMMIT-COHERENCE per phase — the core.** Each phase of a scenario must be coherent at a
  single SHA: at baseline, the seed **and** images **and** git-checkout **and** `sb` binary all at
  **A**; the upgrade moves coherently to **B** (B's checkout, B's migration, B's binary; B's images
  retagged from A). No mixing the seed-pin commit with the run/target commit. This is what kills the
  `stale: built from 18734a42, HEAD is now 50fd4325` incoherence and its downstream self-heal
  procure fail (mode 1). The controlled-B model enforces this **by construction** — A is a pinned
  coherent commit with published seed+service images, B = A + one known migration.
- **(b) Trusted signer in the harness.** Adopt the arc's `trust_arc_signer` (`arc-helpers.sh:24`):
  configure `UPGRADE_TRUSTED_SIGNER_*` for the ephemeral key that signs B **after** install. Fixes
  mode 3 directly; the scenarios get it free by moving onto the controlled-B path.
- **(c) DB-sessions gate vs an active post-recovery worker (mode 2) — needs a call.** Either
  (i) the test sequences the verification install **after** the worker quiesces (the arcs already do
  `wait_for_worker_quiesce`, `arc-helpers.sh:185`) — a harness fix; or (ii) the install
  `Database sessions` gate (`install.go:591`) must tolerate a legitimately-busy worker — a product
  hardening that connects to Fix 9 / `5-install-stage-e-worker-busy` (which *passed*, so this may be
  an uncovered pool-saturation path). **Recommend (i) for the harness now**; file (ii) as a product
  investigation if a real operator could re-run `./sb install` mid-derive.

**Branch naming / lifecycle** — `test/upgrade-target/<run-id>/<spec>` (force-push to origin; the
COMMIT `B_FULL` is authoritative). Created at run start, `git push origin --delete` at run end; a GC
sweep removes orphaned `test/upgrade-target/*` + `test/upgrade-arc-*` older than N days.

**Tradeoff, stated (timing corrected — verified via `gh`):** X keeps two tiers — scenarios
(controlled-B + retag: pure-local loop, no image build) and arcs (controlled-B + real images: CI
build+push) — sharing one B-branch constructor. The B-vs-A time penalty is **modest, not large**: a
full Images build is **~4 min** (runs `28443202473`=3m56s, `28441859104`=4m49s; tentpoles seed ~2m
+ sb ~1m, the other 4 services parallel/cached), and the ~12-min harness VM run is common to **both**
tiers — so the honest net delta is the image build+push+dispatch ≈ **5-8 min**, shared across ~2
canonical Bs per run. (An earlier draft wrongly said 20-30 min — that was the image-wait *timeout
ceiling*, retracted.) I lean X on the **structural** benefit — A keeps a pure-local iteration loop
with no ghcr image push — but with the time gap this small it is a **genuinely close call, the
King's to make**.

## Strategic alternative (Y) — for the King to weigh, not my default

The ~1:1 arc↔scenario overlap means the kill/stall scenarios are nearly the kill/stall arcs with a
different target+dispatch. **Y = collapse to one harness**: delete the scenario wedges, let the
arcs' controlled-B real-image cases cover them, keep only the install-only tests as HEAD-install.
Simpler + higher-fidelity, but **trades the pure-local iteration loop for a real image build+push
per B** (~5-8 min: ~4-min build + CI dispatch/queue — *not* the 20-30 min an earlier draft wrongly
stated) and is a large deletion. Recommend Y only if the King prioritizes one-harness simplicity
over local iteration speed. **This is the one strategic call I need from the King.** Requirements (a)/(b)/(c)
apply either way (Y already satisfies a/b via the arc path; only the scenario-only tests carry c).

## Option-B branch architecture + determinism (the construction IS deterministic)

The King's hope holds — verified at `upgrade-arc-harness.yaml:120-177`. The controlled-B
construction is a repeatable script, not ad-hoc per run (and the same shared constructor serves X):

- **Migration number — deterministic, A-derived.** `V_VERSION = max(A's migration timestamps)+1`,
  `V_VERSION_2 = +2` (`:130-136`). Not wall-clock — derived from A's migration set, so a **pinned A
  yields the same number every run**, and it sorts after every A migration (genuinely pending). This
  is why requirement (a) pinned-A is load-bearing: it is what fixes V_VERSION.
- **Migration content — fixed bytes, hardcoded.** `write_working_v` (`:150-177`):
  `CREATE TABLE public.upgrade_arc_fixture(id PK, note) + INSERT (1,'arc')` plus a 2nd table
  `upgrade_arc_fixture_2`; `write_failing_v` (`:179+`): `DO $$ … RAISE EXCEPTION … $$`. Byte-identical
  every run; **non-idempotent by design** (no `IF NOT EXISTS`) — load-bearing for the after-commit
  deterministic-rollback wedge.
- **Branch architecture — 2 lineages × (B→C) = 4 branches:**
  `test/upgrade-arc-{working,failing}-{migration,fixed-migration}-${RUN_ID}`. **One working pair +
  one failing pair cover every case** (`:240-244`): kill/stall ride working-B; failing/rollback ride
  failing-B. C amends V in place (working) or replaces V_fail with the working migration (failing).
- **Only per-run variance:** the branch *name* (embeds `RUN_ID` — intentional, for matrix isolation)
  and the commit *SHA* (git author/committer/timestamp metadata). The migration **file (number +
  content) is byte-deterministic**. Under Option B the scenarios ride these same canonical Bs.

## Critical files
- `test/install-recovery/fixtures/stage-head.sh` — retag; generalize to `stage-target.sh <B_SHA>`.
- `test/install-recovery/run.sh:239` — `rev-parse HEAD` stamp; add the cheap git-only B-construct step.
- `test/install-recovery/lib/arc-helpers.sh:24 trust_arc_signer`, `:95 arc_to`, `:185
  wait_for_worker_quiesce`, `:267/:294` dispatch — the B-consumption + signer + quiesce flow to share.
- `test/install-recovery/lib/vm-bootstrap.sh:464-480` — `SB_INSTALL_SKIP_SEED` (retired for B scenarios).
- `.github/workflows/upgrade-arc-harness.yaml:130-260` — `build_pair`/writers/`V_VERSION` — **lift
  into `lib/upgrade-target.sh`**.
- `cli/cmd/install.go:591` — the `Database sessions` gate (requirement c, option ii).
- The ~13 `scenarios/*.sh` with `HEAD_SHA=$(… rev-parse HEAD)` — migrate the upgrade ones.

## Verification (the real VM is the only oracle — doc/install-upgrade-testing.md)
- A doc-only commit on HEAD no longer breaks any upgrade scenario; no `stale: built from … HEAD is
  now …` warning (coherence holds); no `statbus-sb:<seed-commit> not found` self-heal fail.
- An unpushed local HEAD no longer breaks a scenario (B is pushed; A is pinned).
- `3-postswap-mid-tx-kill` interrupts the known fixture migration deterministically; signature
  verify passes (signer trusted); no `no real migration delta` assert.
- `./dev.sh test-install-recovery <slug>` (local) + CI matrix `install-recovery-harness.yaml`.

## Open questions for the King
1. **X vs Y** — share-constructor-keep-two-tiers (recommended) vs collapse-to-one-CI-harness.
2. **Scope of pass 1** — foundation = the shared `construct_upgrade_target` + coherent-A pinning +
   harness signer (b) + worker-quiesce sequencing (c-i) + migrate the ~13 upgrade scenarios off HEAD.
   The arc↔scenario dedup, and the product gate (c-ii), are flagged follow-ups regardless of X/Y.
