---
id: STATBUS-102
title: >-
  intentional-fix-rename: rip out amendments.tsv + adopt the canonical
  STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION vocabulary; runtime bless
  by channel
status: Done
assignee: []
created_date: '2026-06-20 00:18'
updated_date: '2026-06-21 20:15'
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
▶ DRIVE DECISION + STATUS (King, 2026-06-20): the King gave EXPLICIT GO (morning) — "I want the two tasks finished by morning, reviewed to a high standard, committed, tests clean." THE RIP-OUT IS COMMITTED + PUSHED:
  • rename (circumvent → intentionally-fix-broken-immutable-migration + cold-agent operator message): 256f62cb9
  • file removal + channel-bless core: 10c26fd9a
  • arc cleanup (strip amendments.tsv from the 3 arc files; bless-leg SKIPPED/PENDING): ddbb52dfc
AC#1/#2/#3 DONE (zero amendments.tsv/circumvent refs anywhere; cut gate env-only, still REFUSES unintended edits — architect-verified release.go:643).
REMAINING (2 items):
  (a) CHANNEL-BLESS SIMPLIFICATION — the bless should read UPGRADE_CHANNEL ONLY, dropping the CADDY_DEPLOYMENT_MODE leak (a front-door concern leaking into upgrade logic). King + architect LIVE decision, pending the King's ratification. Revises 10c26fd9a's migrationChannelClass. Sequences BEFORE STATBUS-097's product change (both touch migrate.go).
  (b) END-TO-END BLESS-PROOF on a VM (AC#5) — DEFERRED, blocked on (a). The working-arc bless-leg is committed as SKIPPED/PENDING in ddbb52dfc; once (a) lands, the working-arc tests channel-bless via UPGRADE_CHANNEL=stable on an ordinary box (identical production code path).
AC status: #4 three-way built + unit-tested (migration_channel_test.go) — will be SIMPLIFIED by (a); #7 channel detection built — simplified by (a); #5 bless-proof + #6 working-arc reconciliation DEFERRED with (b).

----

## Why this matters (read first)
The old name `STATBUS_CIRCUMVENT_IMMUTABLE_MIGRATION` **hid its intent** — "circumvent" reads as *evade / sneak past the gate*, the opposite of a deliberate, principled act. That hidden intent derailed real work (a whole design conversation + prior coding went awry on the misread). King (2026-06-20): this is **profoundly important** — intent must live IN THE NAME so no future reader (human or AI) can misread it.

Ship as ONE clean break (no compat shims):
1. **Remove `migrations/amendments.tsv` entirely** (file + git history; no trace).
2. **Rename the whole mechanism** to ONE canonical vocabulary everywhere — "circumvent" AND "amend" gone.

## What is actually true (VERIFIED)
- **Intent is expressed AT CUT by the env var.** To cut a prerelease with a modified migration you MUST set the var naming that version — a deliberate human act. The cut gate + prerelease-tested-first flow IS the safety net.
- **`amendments.tsv` (the FILE) was the redundant part.** Its only job was auto-conveying the per-version sanctioned list to the box so it would re-stamp at runtime. Under channel-based runtime the box no longer needs that list.

## The principle (King) — what is legitimate
You NEVER touch a released/immutable migration EXCEPT to fix a genuinely BROKEN one. *"If it is not broken it is not an acceptable thing to have intentions to do."* This rules out generic "amend".

## The channel-trust gate decision (King-BLESSED 2026-06-20)
The release-bless RE-STAMPS content_hash trusting the cut gate, with NO runtime tag re-probe. Inductive guarantee: every release is an RC first and the cut gate refuses a modified migration unless the intent env var names it; stable promotes the exact tested RC commit. So every released migration reaching any box was vetted at cut-time → a runtime re-check is redundant AND harmful (false-refuses on shallow `git clone --depth 1` boxes whose tag trees may be absent). Load-bearing invariant: the chain holds iff the cut gate stays unbypassable without the deliberate intent-naming act (which the rename hardened).

## Canonical vocabulary (King-RATIFIED 2026-06-20; applied EVERYWHERE)
| Old | New |
|---|---|
| env `STATBUS_CIRCUMVENT_IMMUTABLE_MIGRATION` | `STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION` |
| `CircumventEnvVar` | `IntentionallyFixBrokenImmutableMigrationEnvVar` |
| `CircumventVersions()` | `IntentionallyFixBrokenImmutableMigrationVersions()` |
| `ParseCircumventVersions()` | `ParseIntentionallyFixBrokenImmutableMigrationVersions()` |
| `AmendmentsFileName`, `ParseAmendmentsFile` | DELETED (file gone) |
| logs/comments "circumventing immutability"/"amend" | "intentionally fixing broken migration N" |

## Working-arc reconciliation (deferred with the bless-proof)
The principle rules out amending a WORKING migration. The 071 working arc amended a working V → re-stamp; under "fix broken only" that's reframed to fix a genuinely BROKEN migration so the bless path is exercised legitimately. Deferred with the bless-proof (item (b) above).

## Ownership + gate
Design = architect → build = engineer → review = architect + foreman → commit = foreman. Driven by the foreman. GO GIVEN (King, 2026-06-20 morning) — see the drive-decision at top; the rip-out is committed. Remaining (a)+(b) sequenced above. Context engrams: #980 (rip-out decision), #982 (corrected understanding), #984 (ratified name), #1052 (channel-trust blessed).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 migrations/amendments.tsv, ParseAmendmentsFile, AmendmentsFileName GONE; zero references to them in cli/ + .github/ + test/ + doc/
- [x] #2 The word 'circumvent' and the generic 'amend' (for this mechanism) appear NOWHERE; the canonical vocabulary (intentionally-fix-broken-immutable-migration) is used at every site, one way only
- [x] #3 The env-var cut gate still REFUSES an unintended migration modification, and accepts a modification ONLY when STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION names that version (safety net preserved)
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Closed 2026-06-21 (King-directed backlog-currency pass; product shipped, the end-to-end proof folds into STATBUS-071). The rip-out + rename + channel-bless are all DONE on master:
- Rename (circumvent → STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION + cold-agent operator message): 256f62cb9.
- amendments.tsv removal + channel-bless core: 10c26fd9a; arc cleanup ddbb52dfc.
- The channel-bless SIMPLIFICATION (item (a) — read UPGRADE_CHANNEL only, drop the CADDY_DEPLOYMENT_MODE leak): shipped as STATBUS-106, committed 81a9082b3, foreman-gated green (holding the push for the King's word).

AC#1/#2/#3 done (zero amendments.tsv/circumvent refs anywhere; cut gate env-only still refuses unintended edits, release.go:643). AC#4 (three-way: localdev→error, edge→redo, release→bless) + AC#7 (channel detection) done via 106.

REMAINING — folds into STATBUS-071's working arc:
- AC#5 (end-to-end bless-proof): now unblocked by 106 — the working arc exercises the release-bless by setting UPGRADE_CHANNEL=stable on the arc box (identical production code path).
- AC#6 (working-arc fixture reframe): from "amend a working migration" to "fix a genuinely broken one", so the bless path is exercised legitimately.
Both are tracked in 071 (the "accept-the-fix / re-stamp" coverage cell + the subsumes-line). 072's doctrine (re-stamp primary, crash-fix-only, no checker, both populations converge) is preserved in the shipped channel-bless.
<!-- SECTION:FINAL_SUMMARY:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-06-20 10:47
---
STATUS UPDATE (foreman, 2026-06-20 morning). RIP-OUT COMMITTED + PUSHED: 256f62cb9 (rename + cold-agent operator message), 10c26fd9a (file removal + channel-bless core, foreman-gated), ddbb52dfc (arc cleanup, bless-leg SKIPPED/PENDING). rg 'amendments|circumvent' across cli/+.github/+test/+doc/ = ZERO. AC#1/#2/#3 done. REMAINING: (a) channel-bless simplification to UPGRADE_CHANNEL-only (drop the CADDY_DEPLOYMENT_MODE leak) — King+architect live, pending ratification; (b) the end-to-end bless-PROOF on a VM (AC#5/#6) — deferred, blocked on (a). King blessed the channel-trust gate decision (no runtime tag re-probe; trust the cut gate).
---
<!-- COMMENTS:END -->
