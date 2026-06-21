---
id: STATBUS-107
title: >-
  plain-upgrade-language: de-jargon the upgrade/recovery vocabulary — "booting
  the new binary", one by one
status: To Do
assignee: []
created_date: '2026-06-21 19:41'
labels:
  - upgrade
  - recovery
  - docs
  - clarity
  - de-jargon
dependencies: []
references:
  - doc/upgrade-timeline.md
  - doc/recovery/
  - cli/internal/upgrade/service.go
priority: medium
ordinal: 107000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why
The upgrade + recovery vocabulary is obtuse — "pre-swap", "post-swap", "Resuming", "positively-behind", "at-target". The King's standard: plain language a reader gets without a glossary. "Booting the new binary" beats "the binary-swap commit boundary". The upgrade is the most safety-critical, most-reviewed code we have — its words must be the clearest.

## The plain forward-vs-rollback decision (the worked example + style anchor — DONE in the doc)
An upgrade has ONE point of no return: the moment the box BOOTS THE NEW BINARY. Before it = reversible prep (incl. the DB backup). After it = committed to new. On a crash-restart, recovery picks FORWARD (finish to new) or ROLL BACK (restore backup -> old). Rule: go forward whenever still possible; roll back only when CONFIRMED stuck behind.
- Crashed before booting the new binary -> roll back (trivial; no backup taken, restart on old).
- Crashed after booting the new binary -> is it already AT the new version?
  - Already at new -> finish forward; NEVER roll back (it may have served new + taken data the backup predates).
  - Confirmed behind -> roll back once to this upgrade's backup -> old.
  - Can't tell (DB unreachable) -> go forward (never destroy on a guess).
- Torn window (killed between a migration committing + being recorded) -> behind -> forward fails "relation already exists" -> roll back -> operator retries.
Landed as the "Forward vs rollback — in plain terms" subsection in doc/upgrade-timeline.md.

## Jargon -> plain map
- pre-swap / post-swap / "the binary-swap" -> before / after BOOTING THE NEW BINARY
- Resuming -> CONTINUING AFTER A CRASH-RESTART
- positively-behind / Behind -> CONFIRMED STUCK BEHIND THE NEW VERSION
- at-target / AtTarget -> ALREADY AT THE NEW VERSION
- ground truth -> WHAT'S ACTUALLY ON DISK (the binary + which migrations ran)
- rollback -> ROLL BACK TO THE OLD VERSION; forward / resume -> FINISH FORWARD TO THE NEW VERSION

## ONE BY ONE — and WHY (do NOT blind-sweep / ruplacer)
Classify EACH site: cosmetic vs load-bearing.
- SAFE (cosmetic): doc prose, code comments, operator-facing log/error strings, Go identifiers, ticket language. Rename freely.
- LOAD-BEARING (careful): the `Phase` enum WIRE values ("post_swap", "resuming") are serialized into the on-disk upgrade flag (UpgradeFlag JSON) by the OLD binary and read back by the NEW binary during recovery. Renaming the wire value BREAKS cross-version recovery (a box mid-upgrade carries the old-format flag). -> rename the Go IDENTIFIERS for clarity but KEEP the wire values (or read both old+new). Per-site judgment, never a sweep.
- The doc references the code's actual Phase values, so doc + code de-jargon are COUPLED: plain prose may name the wire value parenthetically until/unless the code rename lands.

## Targets (one by one)
1. doc/upgrade-timeline.md — the "five phases" + recovery-contract sections -> plain prose (the forward-vs-rollback subsection is the worked example).
2. doc/recovery/* — the recovery design docs -> plain.
3. STATBUS-046's escalation design -> plain language (when it is ratified / built).
4. Code: the `Phase` enum + recover/resume function names -> plain Go identifiers; KEEP the serialized wire values (load-bearing).
5. Operator-facing log + error strings on the upgrade/recovery path -> plain.

Each target = one commit; classify cosmetic-vs-load-bearing first; verify NO serialized/on-disk value changed (the flag must still round-trip old<->new).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 doc/upgrade-timeline.md + doc/recovery/* read in plain language (no pre-swap/post-swap/Resuming/positively-behind/at-target jargon in prose); the forward-vs-rollback plain subsection is the style anchor
- [ ] #2 Code Go identifiers de-jargoned for clarity, but the serialized Phase WIRE values are PRESERVED (or both old+new read) — verified the on-disk upgrade flag still round-trips between an old and a new binary
- [ ] #3 Operator-facing log + error strings on the upgrade/recovery path are plain
- [ ] #4 Each site was classified cosmetic-vs-load-bearing and changed one-by-one (no blind sweep); STATBUS-046's escalation design de-jargoned when it lands
<!-- AC:END -->
