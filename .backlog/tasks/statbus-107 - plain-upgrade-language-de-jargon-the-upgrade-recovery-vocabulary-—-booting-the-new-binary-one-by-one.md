---
id: STATBUS-107
title: >-
  plain-upgrade-language: de-jargon the upgrade/recovery vocabulary — "booting
  the new binary", one by one
status: In Progress
assignee: []
created_date: '2026-06-21 19:41'
updated_date: '2026-06-22 19:30'
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
  - doc/upgrade-vocabulary.md
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
6. doc/diagrams/ — the THREE upgrade/recovery diagrams ONLY: upgrade-timeline.plantuml, upgrade-lifecycle.plantuml, install-recovery.plantuml. Plain prose in the labels/notes (de-jargon: pre-swap/post-swap, "ground truth decides direction", positively-behind, at-target, exit-42-handoff, QuiesceClients, flock, wedge -> the jargon->plain map above). COUPLED to target #4: the function-name + Phase references update WITH the code rename (don't half-rename). Regenerate each .svg from its .plantuml after editing. (The architecture / infra / git / domains diagrams are a DIFFERENT domain — NOT this jargon, OUT OF SCOPE.)

Each target = one commit; classify cosmetic-vs-load-bearing first; verify NO serialized/on-disk value changed (the flag must still round-trip old<->new).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 doc/upgrade-timeline.md + doc/recovery/* + the 3 upgrade diagrams (upgrade-timeline / upgrade-lifecycle / install-recovery .plantuml, with .svg regenerated) read in plain language (no pre-swap/post-swap/Resuming/positively-behind/at-target jargon in prose); the forward-vs-rollback plain subsection is the style anchor
- [ ] #2 Code Go identifiers de-jargoned for clarity, but the serialized Phase WIRE values are PRESERVED (or both old+new read) — verified the on-disk upgrade flag still round-trips between an old and a new binary
- [ ] #3 Operator-facing log + error strings on the upgrade/recovery path are plain
- [ ] #4 Each site was classified cosmetic-vs-load-bearing and changed one-by-one (no blind sweep); STATBUS-046's escalation design de-jargoned when it lands
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Glossary walkthrough — LIVE STATE (architect; updated as we go, King-driven)

RESHAPED: this task is now "establish + apply a SLUG REGIME" (one concept → one kebab `slug` → one plain `message`), not just prose de-jargon. Canonical registry: **doc/upgrade-vocabulary.md** — locked entries land there.

⚠️ GUARDRAIL INVERTED (King, 2026-06-22) — SUPERSEDES this task's Description + AC#2 ("KEEP the wire values"): we WILL change the on-disk serialized Phase values to match the slugs (clean break, NO read-both), with a CLEAN RESTART on an old/unrecognized sentinel. Safety hinges on the upgrade being restart-safe from a post-swap, partially-migrated state — provable ONLY by the install-recovery arcs. PARKED as an arc-gated decision (not yet applied). Doc constraint section marked UNDER REVISION.

LOCKED so far (in the registry):
- PHASES (which sb is running): `old-sb-upgrading` (stored "") → `old-sb-swap` (old sb's last act, exit 42) → `new-sb-swapped` (stored post_swap; arrived, self-heal probe) → `new-sb-upgrading` (stored resuming; running post-swap migrations). The old "Resuming" slug DISSOLVED — it is NORMAL-path = new-sb-upgrading; crash-retry is a recovery action, not a phase.
- UPGRADE STATES (public.upgrade.state, 9 values, snake_case kept): available → scheduled → in_progress → (completed | failed | rolled_back) → (skipped | dismissed | superseded). Full actor map (CLI / web / service) + 26 columns documented. Web writes = browser→PostgREST RLS admin_user; app has no server-side writers.
- SCHEDULING: `claim-upgrade` = sb claims a scheduled upgrade + runs it via executeUpgrade. Runner = systemd service (executeScheduled) OR `./sb install` inline (ExecuteUpgradeInline) — race-safe atomic claim (service.go:1331/3878 → 3911). NOT service-only.

PRINCIPLES (apply to remaining sections):
1. Name the SUBJECT (sb), not bare old/new — many moving parts.
2. WHO-logs-it — one emitter per slug (sb-swap → old-sb-swap / new-sb-swapped).
3. GRAMMAR — ongoing states end -ing; transition events use swap/swapped.
4. WHERE-WE-ARE = Phase; WHERE-WE'RE-GOING = recovery Action.
5. The invoker (service vs install) is an AUDIT field, not part of an action slug.

CARRY-FORWARD (resolve at Recovery): reserve "resuming"/retry vocab for a GENUINE "starting again after a problem" detection (ground-truth-on-reentry, service.go:860) — not the normal hand-off.

NEXT: Recovery — reading state & deciding direction (disk-db-state, already-at-new, cannot-reach-new, state-unknown) → Recovery actions (continue-upgrade, complete-upgrade, roll-back) → Mechanisms & artifacts.

DELIVERY (after the table locks): apply docs → diagrams → code → logs, one site at a time; foreman commits pathspec-scoped; code/wire rename is the LAST pass.
<!-- SECTION:NOTES:END -->
