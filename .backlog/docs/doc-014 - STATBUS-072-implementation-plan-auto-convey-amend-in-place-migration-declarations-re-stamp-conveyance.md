---
id: doc-014
title: >-
  STATBUS-072 implementation plan: auto-convey amend-in-place migration
  declarations (re-stamp conveyance)
type: specification
created_date: '2026-06-18 16:28'
tags:
  - upgrade
  - migrate
  - immutability
  - data-integrity
  - architect-plan
---
# STATBUS-072 implementation plan — auto-convey amend-in-place migration declarations

**Audience:** engineer (build), foreman (review). **Status:** implementable. **One small decision** flagged in §7 (keep vs drop the env var). **Tested via:** STATBUS-071's working + works-for-most arcs (doc-012 §4).

## 0. TL;DR — the re-stamp mechanism ALREADY EXISTS; the gap is CONVEYANCE
The King's doctrine (STATBUS-072 notes) is the spec: re-stamp is the chosen mechanism; you cannot build an outcome-preservation checker (undecidable); the opt-in IS the complete guardrail (a forced declaration of intent); **the ONLY thing to build is AUTO-CONVEYANCE** — carry the declared "migration V is amended, accept its new bytes" from the release to every host's automatic upgrade so the EXISTING re-stamp fires without a human on each box. Validation = the run (STATBUS-071), never inspection.

## 1. Verified current mechanism (file:line — already in place)
- **Detection + re-stamp + hard-fail** = `eagerContentHashCheck` (cli/internal/migrate/migrate.go:1312-1413), called from `runUp` at **migrate.go:737**, BEFORE the pending filter (so it catches in-place edits to already-applied, no-longer-pending migrations).
  - For each RECORDED migration: `liveHash = sha256File(file)` vs `storedHash = db.migration.content_hash`. Match → continue (:1371).
  - MISMATCH **and version ∈ circumvent set** → **RE-STAMP**: `UPDATE db.migration SET content_hash = liveHash WHERE version = …` + continue, no re-run (:1380-1397).
  - MISMATCH **and `MigrationInReleasedTag(version) != ""`** → **HARD FAIL** immutability violation (:1404-1413). ← *this is what the MANY hit today.*
  - MISMATCH + WIP (untagged) → `./sb migrate redo` remediation error (:1414+).
- **The circumvent set source** (THE GAP): `release.ParseCircumventVersions(os.Getenv(release.CircumventEnvVar))` (migrate.go:1326). `CircumventEnvVar = "STATBUS_CIRCUMVENT_IMMUTABLE_MIGRATION"` (immutability.go:31), comma-separated 14-digit versions. Read in TWO layers (immutability.go:22-30): runtime (eagerContentHashCheck) **and** release-cut preflight (cli/cmd/release.go `checkMigrationImmutability`).
- **content_hash is a PLAIN column** — written explicitly with `sha256File(m.Path)` on apply (migrate.go:864/868), NOT NULL, column added by migration 20260426220000. The re-stamp is a plain `UPDATE`.

**Why the MANY crash today:** the env var is manual + ephemeral. The author sets it at RC-cut (so release.go's gate passes), but it is NEVER persisted into the release artifact. The upgrade service spawns `./sb migrate up` inheriting an env where it was never set → circumvent map is EMPTY → a recorded V whose bytes changed and which is in a released tag → HARD FAIL at migrate.go:1404.

## 2. The fix — carry the declaration IN THE RELEASE TREE (recommended: a committed file)
Replace the ephemeral env var with a **committed declaration file** that travels with `git checkout <target>` (which the upgrade does before `./sb migrate up`), read by BOTH consumers.

**Recommended:** a tracked file, e.g. `migrations/amendments.tsv` (engineer picks exact name/format; TSV is greppable + diff-friendly). One row per amendment:
```
# version<TAB>amending_release<TAB>reason (crash-fix only; result-fixes go in a forward migration)
20260521112759	v2026.06.1	V timed out on >1M-row installs; same result, faster
```
Build (minimal — only the conveyance, no checker):
1. New reader `release.ParseAmendmentsFile(projDir) (map[int64]bool, error)` in cli/internal/release/ (next to ParseCircumventVersions) — parses the committed file; same `map[int64]bool` shape; loud on malformed (mirror ParseCircumventVersions' fail-fast). Carry the reason for the log line + audit.
2. **eagerContentHashCheck (migrate.go:1326):** UNION the file with the env: `circumvent = ParseAmendmentsFile(projDir) ∪ ParseCircumventVersions(os.Getenv(...))`. The committed file auto-conveys to every host; the env var stays a local-dev override (§7).
3. **release.go `checkMigrationImmutability`:** same UNION, so the RC-cut gate reads the committed declaration (the author declares IN THE FILE, in the same commit as the amendment — reviewed in the PR diff).
4. The re-stamp + hard-fail logic at :1380-1413 is UNCHANGED — it already does the right thing once `circumvent[version]` is true. The diff is purely the SOURCE of the circumvent set.

**Why a committed file (vs a release manifest field or a public.upgrade row field):** the declaration is a property of the amending commit — a committed file is atomic with the amendment, reviewed in the PR, travels OFFLINE with the checkout (no GitHub manifest fetch, no DB-row plumbing threaded into the migrate subprocess), and preserves the deliberate-intent guardrail (you cannot amend without committing the named declaration). Manifest/row alternatives work but add network/schema plumbing for no gain. (If a non-tree channel is ever needed for untagged-edge amendments, the manifest is the fallback — but amendments are a RELEASE concept, so the tree file suffices.)

## 3. The two populations — both converge (caveat #3)
- **THE FEW** (V crashed/timed-out → **unrecorded**, because every migration is a single BEGIN/END transaction — a crash/timeout rolls back the WHOLE migration, leaving NO partial state): on upgrade to the amended release, V is absent from `db.migration` → it's in the pending set → **forward-applied** as V(fixed) via runPsqlFile (migrate.go:813) → records with the new hash (:868). `eagerContentHashCheck` never touches V (it only checks RECORDED rows). Clean, because the original V's transaction rolled back entirely.
- **THE MANY** (V succeeded → **recorded with OLD hash**): on upgrade, `eagerContentHashCheck` sees `liveHash != storedHash`; V is in the declaration file → **re-stamp** content_hash to the new bytes + continue (:1382), NO re-run (schema already correct) → V stays recorded → not in the pending set → not re-applied.
- Both reach the amended release healthy, data intact. The re-stamp TRUSTS the amendment is result-preserving (the convention, §6) — provable only by the run, not inspection (King's doctrine).

## 4. Detection / re-apply / re-stamp / idempotency (caveats #1, #2)
- **Detection:** content-hash mismatch on a RECORDED version (eagerContentHashCheck). New (unrecorded) migrations are not "detected" here — they forward-apply. Located before the pending filter so it fires for already-applied migrations.
- **Re-apply (few):** ordinary forward apply of V(fixed); idempotent because the original V rolled back (single-tx) → no "relation already exists". The amendment edits BOTH `V.up.sql` AND `V.down.sql` in place (keep down ↔ up consistent for `redo`/`down`).
- **Re-stamp (many):** plain `UPDATE db.migration SET content_hash` (:1382); idempotent (a second run sees liveHash == storedHash → no-op at :1371); no DDL; down-migration irrelevant (no rollback occurs).
- **Idempotency overall:** re-running the upgrade is safe — re-stamp is a no-op once applied; forward-apply skips recorded V.

## 5. ⚠️ GENERATED-ALWAYS caveat (#4) — checked git history; do NOT introduce one
The King's flag is real and verified: commit **036848961 "refactor(upgrade): drop artifacts_ready generated column (#30)"** (preceded by 56bd848f8 splitting `artifacts_ready` → `docker_images_ready`/`release_builds_ready`) — a GENERATED column on `public.upgrade` was dropped. The statistical_unit `hash_slot` GENERATED column has similar scars (doc/db notes "Explicit INSERT column list excludes hash_slot"). **Therefore: detection MUST use the EXISTING plain `content_hash` column** (explicitly written via sha256File at migrate.go:864/868; re-stamped via plain UPDATE at :1382). Do NOT convert content_hash to `GENERATED ALWAYS` — a generated hash slot recreates exactly the class of problem #30 removed. This plan introduces NO generated column and NO schema change to db.migration — it only changes where the circumvent set is sourced.

## 6. Pre/post-release migration discipline (caveat #5) + the convention
- **Pre-first-release:** in-place migration edits are fine (no deployed host has applied it; `MigrationInReleasedTag` returns "" → no gate fires). No declaration needed.
- **Post-release:** editing a released migration is an immutability VIOLATION — sanctioned ONLY via the deliberate amendment declaration (this plan's committed file). This is the one legitimate retroactive edit.
- **The convention (King, the safety rule, NOT a checker):** an amendment is a MINIMAL "make it not crash" fix ONLY — it changes WHETHER the migration finishes, never WHAT it produces. If the RESULT was also wrong, that is a SEPARATE forward migration V+k (the immutability gate already pushes result-fixes forward). The declaration is a forced statement of intent; only the run (STATBUS-071) confirms tautology vs fallacy. Add NO outcome-preservation checker (undecidable — the King struck that as a category error).

## 7. The one small decision (engineer/King)
Keep `STATBUS_CIRCUMVENT_IMMUTABLE_MIGRATION` as a LOCAL-DEV override (UNION with the file — useful while iterating on an amendment before committing the declaration), OR drop it for a single-mechanism clean break (file-only). Recommend KEEP for dev ergonomics (it is not a back-compat shim — it is a distinct pre-commit affordance); the committed file is the canonical production conveyance either way. Cheap to flip.

## 8. Verification (the run is the oracle)
1. **Unit:** `ParseAmendmentsFile` (valid/malformed/empty, mirror ParseCircumventVersions tests); a test that eagerContentHashCheck's circumvent set is the UNION (file ∪ env).
2. **End-to-end via STATBUS-071** (the real proof): the **working→working-fixed** arc (doc-012 §4) exercises the MANY (V succeeds → amend → re-stamp via the conveyed file, no env var, no human). The **works-for-most at BOTH data sizes** variant manufactures BOTH populations in one arc — small data: V succeeds (many → re-stamp); large data: V times out/unrecorded (few → re-run V(fixed)). Assert both hosts reach the amended release healthy + data intact + db.migration.content_hash == new bytes. This is the AUTOMATED conveyance (no per-host env var) the bug is about.

## 9. Critical files
- cli/internal/migrate/migrate.go: `eagerContentHashCheck` :1312-1413 (UNION the file at :1326; logic at :1371/:1380-1397/:1404-1413 unchanged); `runUp` call site :737; apply+stamp :813/:864/:868.
- cli/internal/release/immutability.go: `CircumventEnvVar`/`ParseCircumventVersions` (:31/:41) — add `ParseAmendmentsFile` alongside; `MigrationInReleasedTag` :95 (the released-tag gate, unchanged).
- cli/cmd/release.go: `checkMigrationImmutability` (UNION the file at the cut-time gate).
- migrations/amendments.tsv (NEW committed declaration file).
- No db.migration schema change. No generated column.
