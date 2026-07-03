---
id: doc-025
title: >-
  Seed-consistency foundation — backfill-literal root cause + three-part fix
  (STATBUS-116 first-enable failure)
type: specification
created_date: '2026-07-03 11:53'
tags:
  - seed
  - migrations
  - design
  - statbus-116
---
# Seed-consistency foundation (architect, 2026-07-03)

Design for the STATBUS-116 first-enable failure (run 28657019171). Engineer's diagnosis (tmp/statbus-116-first-enable-failure.md) verified first-hand; his FACTS confirmed, his MECHANISM hypothesis (build cache) FALSIFIED. Engineer builds to this spec.

## 1. VERIFIED MECHANISM — a frozen backfill literal, not a cache artifact

The published statbus-seed:ce383eff is internally inconsistent exactly as the engineer observed (ledger `content_hash[20260218215337]` = cd82bc76 pre-fix; files + seed.json fingerprint post-fix). But NOT via cache:

- ce383eff's own seed job (run 28656755124, job 84987883770) logged `enable-gate=false prior-present=false → PATH=FULL (from empty)` and executed the seed-builder RUN fresh (~70 s of real migration work). A genuine full build.
- Apply-time stamping hashes the file that just ran (migrate.go:947 `sha256File(m.Path)`) — but ONLY for migrations applied AFTER the content_hash column exists. Every migration BEFORE 20260426220000 is recorded hash-less and then BACKFILLED by that migration itself.
- **`migrations/20260426220000_add_db_migration_content_hash.up.sql` hardcodes 344 hash literals frozen at April 26. Line 270: `UPDATE db.migration SET content_hash = 'cd82bc76…' WHERE version = 20260218215337;`**
- The July-2 sanctioned in-place ORDER-BY fix (8b5912a9a) changed the FILE (sha 71befa05, verified via git show at 8b5912a9a~1 / 8b5912a9a / HEAD) but nothing updates the frozen literal.

⇒ **Every full-from-empty build since 2026-07-02 21:18 deterministically stamps the stale literal.** All seeds published since then (ce383eff, a62ce89b2, …, today's) are inconsistent. Republishing without a code fix reproduces it byte-for-byte — a "forced no-cache republish" is a non-option.

Why ce383eff's own build survived: eagerContentHashCheck (migrate.go:820) runs at the START of migrate up — the from-empty ledger is empty then; the stale row is created mid-run and never re-checked. The first ENABLED run then restored that ledger, the eager sweep saw the mismatch, and the hermetic builder's .env has no UPGRADE_CHANNEL → channelLocalDev → release.MigrationInReleasedTag → `git tag -l` → exit 128 (no .git in-stage, by design).

Local dev/seed DBs are consistent (71befa05) only because the engineer healed them by hand while building the fix — CI has no such heal.

## 2. DEPLOYED-BOX SEVERITY — no real install path broken today

- **Fresh standalone/private installs (the real operator path, incl. Africa boxes): SELF-HEAL.** Non-development modes default `UPGRADE_CHANNEL=stable` (config.go:379-383) → channelRelease → the eager check's designed BLESS re-stamps stale→current silently (migrate.go:1462-1485, the STATBUS-102 flow — this in-place fix is precisely the sanctioned class it exists for). Install completes; DB ends consistent.
- **Fresh installs on `edge` channel: LATENT TRAP, not currently exercised.** Feb migration ≠ latest → edge falls through to the localDev branch → MigrationInReleasedTag finds it in v2026.06.0-rc.04 (verified: the tag carries the PRE-fix blob) → hard immutability error whose remediation advice (`git checkout <tag> -- …`) would REVERT the sanctioned fix. New edge installs are rare; existing edge boxes upgrade via migrations on an existing consistent ledger, so they never hit the backfill. Fold the wrong-advice repair into the STATBUS-102 deep-edge follow-up.
- **Dev boxes:** unaffected (no seed restore; create-db + local redo discipline).
- **CI harnesses** (install-recovery, upgrade-arc): install standalone → stable → self-heal → green. If any harness asserts "no ⟳ re-stamp lines in migrate output", it will flag — treat as informative, not a regression.

## 3. THE FIX — three parts, one invariant each

**Invariant A — a from-empty build is self-consistent by construction.**
In runUp's apply loop, at the moment `hasContentHash` flips false→true (migrate.go:930-935 — the column-add migration just applied IN THIS RUN), re-stamp every existing db.migration row whose content_hash differs from `sha256File(findUpFile(version))`; skip versions with no matching file; log each re-stamp loudly. This runs ONLY in runs that apply 20260426220000 itself (from-empty builds; ancient pre-April boxes crossing it), where the on-disk files are the operative truth — the literals become advisory and are corrected seconds after they execute. NO edit to the released backfill migration (editing it would itself be an in-place edit of a released migration — the same class recursing). Future sanctioned in-place edits of pre-April-26 migrations need no literal maintenance ever again.

**Invariant B — an inconsistent artifact is impossible to publish.**
DumpSeed (cli/cmd/seed.go:436) gains a pre-dump assert: every db.migration.content_hash in the database being dumped must equal sha256 of the matching on-disk migration file (skip file-less rows). Any mismatch → hard build failure naming the version + both hashes. This is the publish gate the class slipped through.

**Invariant C — the hermetic stage never runs git; a stale restored prior self-heals to FULL.**
The engineer's proposal, confirmed, with one amendment: carry the mode via the EXISTING channel mechanism instead of new plumbing. The seed-builder's generated .env (postgres/Dockerfile:488-504) gains `UPGRADE_CHANNEL=seed-build`; migrationChannelClass (migrate.go:1597) learns `seed-build` → new channelSeedBuild; eagerContentHashCheck's mismatch switch returns a typed `migrate.ErrStaleRestoredMigration{Version}` for that channel — no git, ever, in-stage (today's accidental localDev-in-stage becomes an explicit, named channel). `sb db seed build`'s incremental branch catches it (errors.As) → DROP the restored seed DB → rerun the FULL path (CreateSeedDb → migrate → dump, depth 0) with a loud "restored prior stale on migration N → full rebuild" log. With A+B this fires only against the currently-published inconsistent seeds and any future unforeseen corruption — defense in depth, and it removes the structurally-wrong git dependency from the stage regardless.

Rejected: host-side per-migration-hash validation of the prior (engineer's alternative) — needs a seed.json schema addition and duplicates the in-stage check; B already guarantees future artifacts, C covers restored ones. Rejected: fixing the literal in 20260426220000 — edits a released migration (recursive class) and re-creates the maintenance trap A abolishes.

## 4. RE-ENABLE SEQUENCE — engineer's, confirmed with one amendment

1. Land A+B+C (one commit set; engineer builds, architect reviews).
2. Next master push: flip stays FALSE → FULL build → A makes it consistent, B PROVES it (assert executed in the publishing build — the artifact is consistency-attested, not assumed).
3. Verify seed job green. No manual artifact inspection required — B is the check, in-band.
4. King re-sets SEED_INCREMENTAL_ENABLED=true. First enabled run restores the newest (consistent) prior → green. If the ancestor walk ever lands on an older inconsistent seed, C self-heals to full. Kill-switch (variable→false) unchanged throughout.
5. AMENDMENT: no interim republish, no operator action — stable-channel installs self-heal today (see §2), and republishing before A lands would just re-mint the inconsistency.

## 5. Build touchpoints (for the engineer)

- cli/internal/migrate/migrate.go — channelSeedBuild in the enum + migrationChannelClass (≈1597); typed ErrStaleRestoredMigration; eagerContentHashCheck switch arm (≈1461); re-stamp-at-flip in runUp (≈930-935, extract a restampBackfilledHashes helper).
- cli/cmd/seed.go — DumpSeed pre-dump ledger==files assert (shared helper with the re-stamp's comparison loop).
- cli/cmd/seed_build.go — incremental branch: errors.As catch → drop seed DB → full-path rerun (reuse the existing full branch; newDepth 0; loud log).
- postgres/Dockerfile:488-504 — add UPGRADE_CHANNEL=seed-build to the generated .env.
- Tests: Go unit tests for the channel routing + fallback decision + re-stamp helper (pure parts); the run is the only oracle for the rest — prove by pushing and watching the seed job (disabled full first, then the flip).
