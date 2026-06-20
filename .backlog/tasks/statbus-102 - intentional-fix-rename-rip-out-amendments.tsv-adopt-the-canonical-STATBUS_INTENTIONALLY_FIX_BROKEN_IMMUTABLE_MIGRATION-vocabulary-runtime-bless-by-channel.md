---
id: STATBUS-102
title: >-
  intentional-fix-rename: rip out amendments.tsv + adopt the canonical
  STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION vocabulary; runtime bless
  by channel
status: To Do
assignee: []
created_date: '2026-06-20 00:18'
updated_date: '2026-06-20 00:29'
labels:
  - upgrade
  - migration-immutability
  - clean-code-ship
  - architect-plan
  - naming
dependencies: []
documentation:
  - doc-014
priority: high
ordinal: 102000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why this matters (read first)
The old name `STATBUS_CIRCUMVENT_IMMUTABLE_MIGRATION` **hid its intent** — "circumvent" reads as *evade / sneak past the gate*, the opposite of a deliberate, principled act. That hidden intent derailed real work (a whole design conversation + prior coding went awry on the misread). King (2026-06-20): this is **profoundly important** — intent must live IN THE NAME so no future reader (human or AI) can misread it.

Ship as ONE clean break (no compat shims):
1. **Remove `migrations/amendments.tsv` entirely** (file + git history; no trace).
2. **Rename the whole mechanism** to ONE canonical vocabulary everywhere — "circumvent" AND "amend" gone.

## What is actually true (VERIFIED — do not repeat the earlier misread that the file was the intent-channel)
- **Intent is expressed AT CUT by the env var.** To cut a prerelease with a modified migration you MUST set the var naming that version — a deliberate human act. `checkImmutabilityGate` (cli/cmd/release.go:523) → `checkMigrationImmutability` (:638; skip-if-set :691-699; fix text :734). `./sb release stable` (:869) promotes the EXACT tested RC commit (:955-956, :1056). The cut gate + prerelease-tested-first flow IS the safety net.
- **`amendments.tsv` (the FILE) is the redundant part.** Its only job was auto-conveying the per-version sanctioned list to the box so it would re-stamp at runtime. Under channel-based runtime (below) the box no longer needs that list.
- `CircumventVersions = ParseAmendmentsFile(amendments.tsv) ∪ env` (cli/internal/release/immutability.go:120-133). Remove the file → the set is env-ONLY.

## The principle (King) — what is legitimate
You NEVER touch a released/immutable migration EXCEPT to fix a genuinely BROKEN one. *"If it is not broken it is not an acceptable thing to have intentions to do."* This rules out generic "amend" — including the old "result-preserving re-stamp of a WORKING migration" case. See Working-arc reconciliation.

## Canonical vocabulary (King-RATIFIED 2026-06-20; apply EVERYWHERE, one way only)
| Old | New |
|---|---|
| env `STATBUS_CIRCUMVENT_IMMUTABLE_MIGRATION` | `STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION` |
| `CircumventEnvVar` | `IntentionallyFixBrokenImmutableMigrationEnvVar` |
| `CircumventVersions()` | `IntentionallyFixBrokenImmutableMigrationVersions()` |
| `ParseCircumventVersions()` | `ParseIntentionallyFixBrokenImmutableMigrationVersions()` |
| `AmendmentsFileName`, `ParseAmendmentsFile` | DELETED (file gone) |
| logs/comments "circumventing immutability"/"amend" | "intentionally fixing broken migration N" |
("INTENTIONALLY" settled by a unanimous cold poll of operator+mechanic+engineer — it carries the deliberate-override / `--force` weight. Keep it.)

## Exact sites (no guessing)
1. **cli/internal/release/immutability.go** — rename `CircumventEnvVar` (:32), `ParseCircumventVersions` (:42), `CircumventVersions` (:120, now env-ONLY: drop the file union); DELETE `AmendmentsFileName` (:76) + `ParseAmendmentsFile` (:84-109); rewrite header comments (:13-32, :62-76, :111-119).
2. **cli/cmd/release.go** — `checkImmutabilityGate` (:523), `checkMigrationImmutability` (:638; read :644; skip :691-699; log :707; error/fix text :578, :734-735): rename refs; reword to "intentionally fix broken migration"; cut gate stays (env-only).
3. **cli/cmd/release_verify.go** — comment :82-85; read :91; logs :143-144, :151.
4. **cli/internal/migrate/migrate.go** — `eagerContentHashCheck` (reads :1328; comment :1321-1326; bless branch :1382-1398): THE product change — replace the circumvent-list bless with CHANNEL-based bless (release/prerelease → bless an applied broken-fix; dev → redo; local → error). Reconcile with `MigrationInReleasedTag` (:1402) + `currentMigrationTarget` (:1416-1462). Reword log :1396.
5. **.github/workflows/upgrade-arc-harness.yaml** — construct: remove the C-leg appending to `migrations/amendments.tsv` (working scenario, ~:182-190) + the amendments.tsv comments; working-arc bless driven by channel.
6. **test/install-recovery/arcs/working-arc.sh + failing-arc.sh** — update amendments.tsv comments.
7. **Tests** — `cli/internal/release/amendments_test.go` (delete/rewrite), `immutability_test.go` (rename); ADD tests for the three-way runtime (local=error, dev=redo, release=bless/apply).
8. **Docs** — grep `doc/` + `.backlog/` for `amendments.tsv`/`circumvent` and update (doc-012, STATBUS-072, doc/upgrade-timeline.md).
9. **STATBUS-071** — realign AC#1 ("C re-stamps content_hash" via amendments.tsv) + working-arc to channel-bless.

## Working-arc reconciliation (honest consequence — resolve at design)
The principle rules out amending a WORKING migration. The 071 working arc amends a working V (prepend comment) → re-stamp; under "fix broken only" that's illegitimate. Decide at design: (a) reframe the working arc to fix a genuinely BROKEN migration so the bless path is exercised legitimately, or (b) retire the working-amend test. Architect owns this call.

## Channel detection (prerequisite — verify before building)
Runtime bless-by-channel needs reliable detection of the box's channel (local-dev / dev.statbus.org / prerelease / release). `currentMigrationTarget` (migrate.go:1446) infers dev/seed from PGDATABASE — confirm it (or deployment config) can distinguish the needed channels; if not, building that detection is step 0.

## Ownership + gate
Design (channel-bless + working-arc reconciliation) = architect → build = engineer → review = architect + foreman → commit = foreman. Driven by the foreman. **NO CODE until the King's explicit GO** (decree, rule-above-all — gate-adjacent). Context engrams: #980 (rip-out decision), #982 (corrected understanding), #984 (ratified name).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 migrations/amendments.tsv, ParseAmendmentsFile, AmendmentsFileName GONE; zero references to them in cli/ + .github/ + test/ + doc/
- [ ] #2 The word 'circumvent' and the generic 'amend' (for this mechanism) appear NOWHERE; the canonical vocabulary (intentionally-fix-broken-immutable-migration) is used at every site, one way only
- [ ] #3 The env-var cut gate still REFUSES an unintended migration modification, and accepts a modification ONLY when STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION names that version (safety net preserved)
- [ ] #4 Runtime three-way handling holds, each covered by a test: local dev -> error; dev channel -> redo (down+up); release/prerelease -> adjudicate (not-applied -> apply; applied broken-fix -> bless)
- [ ] #5 The broken-migration-fix (bless) path works end-to-end on the upgrade arc (STATBUS-071) via the channel mechanism, NOT via amendments.tsv
- [ ] #6 Working-arc reconciliation resolved: reframed to fix a genuinely broken migration, or retired
- [ ] #7 Channel detection verified or built so the runtime reliably distinguishes the channels the three-way handling needs
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
=== 072 GROUNDING — this task SUPERSEDES the amendments.tsv deliverable of STATBUS-072 (DONE, committed 24907e2f8; design = doc-014) ===

072 BUILT migrations/amendments.tsv as the AUTO-CONVEYANCE of amend-intent to the RUNTIME box: the env var is NOT set on the Albania box during an automated upgrade, so the file was how the box learned which migration to re-stamp/bless. This task replaces that file with channel-trust.

PRESERVE 072's still-valid doctrine (the rip-out changes only the CONVEYANCE + NAMING, NOT this):
- RE-STAMP is primary over rollback (DEPTH-ASYMMETRY: re-stamp is O(1) however far back the migration is; a deep downgrade is expensive AND potentially incorrect — later migrations were written against the buggy output).
- CRASH-FIX-ONLY convention = the King's 'fix broken only' (this session, same principle two sessions apart): an amendment changes WHETHER a migration finishes, never WHAT it produces; a result-fix goes in a LATER FORWARD migration (V+k), never the amendment.
- NO CHECKER (undecidable): outcome-preservation for all data is undecidable; the declaration is a forced DECLARATION OF INTENT, not a check; validation = running it everywhere. channel-bless must NOT add a checker.
- BOTH host populations converge: THE MANY (applied V, recorded old bytes) -> bless/re-stamp, no re-run; THE FEW (V crashed, unrecorded) -> re-run the corrected V fresh.

CONVEYANCE-REPLACEMENT (load-bearing): channel-bless REPLACES the file's runtime role — the box must STILL bless THE MANY (now by trusting the cut gate / channel, instead of reading amendments.tsv). Deleting the file WITHOUT landing channel-bless regresses 072's exact bug ('the MANY hard-fail the immutability gate on automated upgrade'). The file's runtime per-version check was redundant WITH THE CUT GATE (which already filters to only-declared amendments) — which is exactly why channel-trust can replace it (the King's point).

FLAG: 072 is DONE/signed-off; closing this task reverses its committed deliverable (the King flagged amendments.tsv for rip-out, so this is intended). Relate/annotate 072 when this lands.
<!-- SECTION:NOTES:END -->
