---
id: doc-025
title: >-
  Seed-fidelity foundation — ledger + cluster-effect infidelity, unified design
  (STATBUS-116 first-enable + arc 28656025811)
type: specification
created_date: '2026-07-03 11:53'
updated_date: '2026-07-03 11:58'
tags:
  - seed
  - migrations
  - design
  - statbus-116
---
# Seed-fidelity foundation (architect, 2026-07-03; unified rev 2)

THE INVARIANT: **a seed-restore followed by `migrate up` must yield a box equivalent to migrate-from-empty.** Two independent failures of it surfaced within a day — same class, two carriers:

- **Instance 1 (metadata infidelity):** the seed's db.migration ledger carries a content_hash that disagrees with the migration files → the STATBUS-116 first-enable failure (§1).
- **Instance 2 (effect infidelity):** the seed ledger claims a migration applied while its CLUSTER-level side effect is structurally absent from the dump → the arc-28656025811 HEALTHCHECK_REST_DOWN recurrence (§1b).

Both engineer/mechanic evidence sets verified; the cache hypothesis for instance 1 FALSIFIED; the foreman's pg_db_role_setting hypothesis for instance 2 CONFIRMED (mechanic: pg_restore -l of statbus-seed:8a45e294 = 2400 TOC entries, zero authenticator/ALTER ROLE; ledger row 377 claims 20260703104910 applied; install path = seed-restore per install.go:1534/1617 + seed.go:292).

## 1. Instance 1 mechanism — the frozen backfill literal (VERIFIED)

- ce383eff's own seed job (run 28656755124, job 84987883770) logged `PATH=FULL (from empty)` and executed fresh (~70 s) — NOT a cache artifact.
- Apply-time stamping hashes the file that ran (migrate.go:947) — but only AFTER the content_hash column exists. Everything before 20260426220000 is backfilled by that migration's **344 hash literals frozen at April 26** (line 270 = the pre-fix hash for 20260218215337).
- The July-2 sanctioned in-place ORDER-BY fix (8b5912a9a) changed the file (71befa05, verified via git show) but no literal → **every full-from-empty build since 2026-07-02 21:18 is deterministically inconsistent**. All seeds published since are affected. Republish without a code fix re-mints it byte-for-byte.
- eagerContentHashCheck (migrate.go:820) runs BEFORE apply — empty ledger in a from-empty build — so the builder never sees its own inconsistency; the next migrate up over the restored ledger does. In the hermetic stage the .env has no UPGRADE_CHANNEL → accidental localDev → released-tag git probe → exit 128.

## 1b. Instance 2 mechanism — cluster-level effects cannot ride a pg_dump (VERIFIED)

- `ALTER ROLE authenticator SET default_transaction_read_only = off` (migration 20260703104910, the STATBUS-110 exemption) writes pg_db_role_setting — a CLUSTER catalog. pg_dump is database-scoped; pg_dumpall alone carries it. Structurally undumpable — no republish can ever help.
- The seed builder's cluster ran the migration (ledger row present); the restored VM's cluster never did. migrate up sees "applied" and legitimately skips. The exemption is NEVER armed on any seed-restored box → the first window-crossing upgrade deadlocks at REST /ready exactly as pre-fix → health check fails → rollback. Explains: base-A installs healthy (window off), only forward-apply deadlocks, rollback arc passes (window lifts at its terminal), local repro green (dev applied the migration directly).
- **The class is systemic, not a one-off** — migration sweep found PRE-EXISTING victims: 20240102000000's `ALTER ROLE authenticated SET statement_timeout/lock_timeout` and `ALTER ROLE authenticator SET session_preload_libraries = safeupdate` are ALSO missing on every seed-restored box (silent loss of the safeupdate guard + timeouts). And the precedent that proves the designed home: **migrations/post_restore.sql already exists exactly for this** — its header names the class ("cluster-level state (role grants) is never in pg_dump") and already re-arms 20240103000000's role-membership GRANTs. It runs from `sb migrate up` after every migration run, even zero-pending (migrate.go:1015), as admin. The 110 fix simply landed in the wrong home.

## 2. Deployed-box severity — unified verdict

- **Instance 1: no real install path broken today.** Fresh standalone/private installs default UPGRADE_CHANNEL=stable (config.go:379-383) → channelRelease → designed silent BLESS re-stamp on first migrate up (migrate.go:1462-1485). Latent trap only on fresh edge-channel installs (immutability error with WRONG revert-the-fix advice) → fold into the STATBUS-102 deep-edge follow-up.
- **Instance 2: bigger tail — every seed-restored box's FIRST window-crossing upgrade fails (then rolls back data-safe).** Today: arc VMs (proven red); production niue slots + rune are OLD installs that MIGRATED the exemption → have the GUC → SAFE; recent fresh installs via seed-restore are armed-less and will fail their first upgrade until the fix ships. The external-standalone rollout (the strategic arc) would have shipped broken-first-upgrade to every new operator box — caught pre-release; rc.05 not cut; nothing released carries window+seed together. Plus the silent pre-existing loss of safeupdate/timeouts on all seed-restored boxes (no crash, real config degradation).
- **Interim recommendation: NO republish for either instance** (1: deterministic re-mint; 2: structurally undumpable), no operator action. The hotfix is code (§3 D/E) and small — land it, and the arc re-run is the proof.

## 3. THE FIX — five parts, one invariant each

**A — from-empty builds are metadata-consistent by construction.** At the hasContentHash false→true flip in runUp (migrate.go:930-935), re-stamp every db.migration row whose content_hash ≠ sha256File(findUpFile(version)); skip file-less rows; loud log. Literals become advisory; the released backfill migration is NEVER edited (that would recurse the in-place-edit class). Future sanctioned in-place edits of pre-April-26 migrations need no literal maintenance.

**B — an inconsistent artifact is impossible to publish.** DumpSeed (cli/cmd/seed.go:436) asserts, pre-dump, every ledger content_hash == sha256 of the matching on-disk file; mismatch → hard build failure naming version + both hashes.

**C — the hermetic stage never runs git; a stale restored prior self-heals to FULL.** Seed-builder .env (postgres/Dockerfile:488-504) gains explicit `UPGRADE_CHANNEL=seed-build`; migrationChannelClass (migrate.go:1597) learns channelSeedBuild; eagerContentHashCheck returns typed `ErrStaleRestoredMigration{Version}` for that channel; `sb db seed build` catches → drop restored seed DB → loud FULL rebuild (depth 0). Defense in depth over A+B; removes the structurally-wrong git dependency regardless.

**D — cluster-level effects live in their designed home, re-armed on every box.**
- REMOVE migration 20260703104910 entirely (up+down; it is in NO released tag — verified `git tag --contains` empty — so the pre-release window applies; deployed boxes that already ran it keep a harmless orphan ledger row, which eagerContentHashCheck skips via findUpFile-miss, migrate.go:1446-1451). ADD `ALTER ROLE authenticator SET default_transaction_read_only = off;` to post_restore.sql with the doc-023 rationale comment.
- MIRROR (do not edit) the released 20240102000000 GUCs into post_restore.sql: `ALTER ROLE authenticated SET statement_timeout = '120s'; ALTER ROLE authenticated SET lock_timeout = '8s'; ALTER ROLE authenticator SET session_preload_libraries = safeupdate;` — the same duplicate-into-post_restore pattern the GRANTs already use.
- Ordering guarantee preserved: post_restore runs inside the same migrate step (upgrade step 10) that preceded the REST restart (step 11); the exemption is armed before /ready is consulted, on every box, every migrate up, idempotently.
- SUB-DECISION (recommend, foreman may trim): post_restore.sql currently WARN-only on failure (migrate.go:1021). Its charter is "idempotent repairs required for correctness" — a failed repair should fail the migrate loudly. Recommend flipping to hard-fail; it runs as admin and every statement is idempotent, so a failure means the box is genuinely broken.

**E — the class cannot re-enter: static gate on cluster-scoped statements in migrations.** Pre-commit/CI check (same family as the existing hooks; fast, actionable): new/changed migrations/*.up.sql containing `ALTER ROLE`, `CREATE ROLE`, `DROP ROLE`, `ALTER SYSTEM`, `TABLESPACE`, or role-membership `GRANT <role> TO <role>` → error pointing at post_restore.sql (idempotent re-arm) / init-db.sh (cluster birth). Existing released migrations grandfathered (the gate diffs, not sweeps).

Rejected: host-side prior validation via seed.json per-migration hashes (schema growth, redundant with B+C); fixing the backfill literal in-place (recursive class); carrying cluster state in the seed artifact (pg_dumpall-globals sidecar — heavyweight, and post_restore already exists as the idempotent home with precedent).

## 4. Sequence

1. Engineer builds A+B+C+D+E as one package (disjoint code; architect reviews).
2. Push → arc re-run proves D (base-A seed-restore → post_restore arms exemption → forward-apply upgrade passes health check) AND the seed job (flip still FALSE) builds FULL: consistent by A, ATTESTED by B in-band.
3. Both oracles green → King re-sets SEED_INCREMENTAL_ENABLED=true. First enabled run restores the consistent prior; C self-heals if the walk ever lands on an older inconsistent seed. Kill-switch unchanged.
4. No interim republish, no operator action, at any point.

## 5. Build touchpoints

- cli/internal/migrate/migrate.go — channelSeedBuild (≈1597); ErrStaleRestoredMigration; eager-check arm (≈1461); restampBackfilledHashes at the flip (≈930-935); post_restore hard-fail (≈1015-1021, sub-decision).
- cli/cmd/seed.go — DumpSeed pre-dump ledger==files assert (share the comparison helper with A).
- cli/cmd/seed_build.go — incremental branch errors.As catch → drop seed DB → full rerun, loud.
- postgres/Dockerfile:488-504 — UPGRADE_CHANNEL=seed-build in the generated .env.
- migrations/ — DELETE 20260703104910_*.{up,down}.sql; post_restore.sql += the four ALTER ROLE statements (110 exemption + 20240102 mirrors) with rationale comments.
- .claude/hooks or CI — the cluster-statement gate (E).
- Oracles: the arc harness re-run + the seed job. Go unit tests for the pure parts (channel routing, fallback decision, re-stamp helper).
