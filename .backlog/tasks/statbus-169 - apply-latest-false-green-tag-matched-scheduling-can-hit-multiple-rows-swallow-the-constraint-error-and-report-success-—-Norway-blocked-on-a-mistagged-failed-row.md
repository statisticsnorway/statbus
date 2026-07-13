---
id: STATBUS-169
title: >-
  apply-latest-false-green: tag-matched scheduling can hit multiple rows,
  swallow the constraint error, and report success — Norway blocked on a
  mistagged failed row
status: To Do
assignee:
  - '@engineer'
created_date: '2026-07-13 00:16'
updated_date: '2026-07-13 01:34'
labels:
  - upgrade
  - production
  - fail-fast
  - deploy
dependencies: []
priority: high
ordinal: 170000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a deploy poke either schedules exactly one upgrade or fails loudly saying why — never exit 0 with nothing scheduled. The COMMIT is authoritative; a tag on a row whose commit_sha the tag does not point at is corrupt data the machinery must never produce (and must refuse, loudly, if found).
> FOUND: 2026-07-13 night — Norway's deploy went workflow-green TWICE with zero effect on the box; caught only because the foreman read the box instead of trusting the workflow.
> COMPLEXITY: engineer — registration/tag-sync correctness + apply-latest robustness + tests; ships in the next RC; Norway converges by deploying it.

THE EVIDENCE CHAIN (rune.statbus.org, box on v2026.06.0-rc.04; deploy runs 29213350249 + 29214859398):
1. FIRST poke (23:27:56Z): `./sb upgrade apply-latest` resolved "Channel prerelease: latest version is v2026.07.0-rc.01", ran its schedule-UPDATE → `Scheduled upgrade: UPDATE 0` (the box had not yet registered the RC — the service's own check registered row 223 as `available` 43 seconds LATER), sent NOTIFY anyway, exited 0 → workflow GREEN, box unchanged. Race: the poke can arrive before the box's registration; "UPDATE 0" is not treated as failure.
2. SECOND poke (00:12:36Z, row 223 now exists): `Scheduled upgrade: ERROR: duplicate key value violates unique constraint "upgrade_single_scheduled"` — then NOTIFY, exit 0, workflow GREEN again, box unchanged. psql runs without ON_ERROR_STOP on this path; the ERROR lands in the captured output and is PRINTED as if it were the scheduled row.
3. WHY the constraint fired with ZERO scheduled rows existing: the rc.04 UPDATE (v2026.06.0-rc.04:cli/cmd/upgrade.go:196-209) matches `:'target' = ANY(commit_tags) OR commit_sha = :'target' OR commit_sha LIKE :'target' || '%'` — ALL matching rows. On rune TWO rows carry the tag: row 223 (available, commit 143cece86 — correct: the RC tag points there) and row 222 (failed, commit a1b58193d, commit_tags={v2026.07.0-rc.01} — WRONG: the tag does not point at that commit). One statement setting two rows scheduled violates the partial unique index → whole UPDATE rolls back → nothing scheduled, error swallowed.

THREE DEFECTS, each its own fix (verify each against CURRENT master first — the box runs rc.04; master may have moved):
A. TAG MISASSIGNMENT (data corruption class): find how registration/tag-sync attached v2026.07.0-rc.01 to a row whose commit_sha is a1b58193d (a master commit from earlier that day whose row FAILED signature verification). The existing pruner ("Pruned deleted tags") only removes deleted tags — it never validates tag→commit pointing, so the corruption is durable. Fix the producer; add the guard: a row's commit_tags may only contain tags that point at its commit_sha (validate at write; loud refuse on violation — no silent repair, per no-standing-self-heal).
B. MULTI-ROW SCHEDULING: the UPDATE must pick exactly ONE row (the tag-pointed commit's row; commit-authoritative resolution — resolve tag→commit first via the canonical vocabulary, then match commit_sha alone). A tag should never be the row selector.
C. FALSE-GREEN: apply-latest must fail non-zero on UPDATE 0 (distinguish "not yet registered — will retry" from success; the deploy workflow should retry/poll, not report green) and on ANY psql error (ON_ERROR_STOP + check). "The workflow is green" must imply "the box scheduled the upgrade".

FLEET STATE at filing: dev (edge) healed and completed on 17d47c5e2 — its apply-latest matched by commit prefix, single row, unaffected. Demo (prerelease): zero rows carry the tag — clean so far. Norway: BLOCKED by the mistagged row 222; converges when the fixed binary reaches it (next RC), or when row 222's wrong tag is corrected through sanctioned machinery — NO manual writes. The six-slot cloud wave HOLDS per the King's sequence (Norway's gate not passed).

ORACLE: (i) unit tests on the three fixes; (ii) THE REAL ONE: Norway's deploy poke schedules exactly one row and the box completes v2026.07.0-rc.01+ through the normal path; (iii) a poke against a not-yet-registered version fails loudly (or retries to success) — never exit-0-no-op.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tag-to-row assignment is commit-authoritative: a row's commit_tags can only contain tags pointing at its commit_sha, enforced at write with a loud refusal; the rune misassignment's producer is found and fixed (cite the code path)
- [ ] #2 apply-latest schedules exactly ONE row, resolved tag→commit first; multi-match is structurally impossible
- [ ] #3 apply-latest fails non-zero on UPDATE 0 and on any psql error (ON_ERROR_STOP); the deploy workflow's green implies the box scheduled the upgrade
- [ ] #4 Norway completes v2026.07.0-rc.01 or newer through the normal path — the run is the oracle; the six-slot wave resumes after
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (relayed by foreman)
created: 2026-07-13 00:29
---
DESIGN RULED (architect, 2026-07-13 night) + master-verification reshape (engineer). MASTER ALREADY CLOSED defects B/C's rc.04 mechanisms (the 086 register→schedule refactor: RunSchedule is single-commit pgx with RowsAffected-0 → error and error propagation). The LIVE bug is narrower: resolveUpgradeTarget's release-tag branch trusts the DB column (LookupSHAByTag, LIMIT 1, no ORDER BY — nondeterministic across rune's two tag-carrying rows) and only falls back to git when the tag is ABSENT. 

THE RULING — commit_tags is a CACHE of git state (the King's commit-authoritative doctrine decides it: tags are after-the-fact, movable, prunable; a mirror of movable references goes stale BY DESIGN). Judged by WHEN an entry is wrong: at WRITE time, appending a non-pointing tag is machinery writing a false fact → the write-guard REFUSES loudly (fail-fast). At REST, a moved tag is staleness from legitimate tag movement → refreshing against the source of truth is the cache's normal contract, NOT a standing self-heal (that rule targets quiet repairs of machinery failures, not a cache honoring its source). So the existing pruner — which already drops DELETED tags — is EXTENDED to drop MOVED tags, one log line per drop naming tag, old row, and current target. Norway's row 222 heals on the pruner's normal cycle: machinery-executed, no manual write, no one-off script.

Resolver doctrine: git-first BY DEFINITION; a DB fallback may exist only for source-unreachable moments, must never override readable git, and needs a NAMED consumer that genuinely schedules with git unreachable — or it gets deleted (a fallback without a named consumer is dead defensive cover). Mismatch shape: both readable and disagreeing → trust git, log the stale entry loudly, pruner cleans on cycle. Producer-trace of the original tag-move event: finish for the record; nothing gates on it. Architect rules final on the frozen code.
---

author: engineer (relayed by foreman)
created: 2026-07-13 00:49
---
PRODUCER TRACE (read-only rune SELECT; the incident's named history — corrects both prior hypotheses). Row 222: commit a1b58193d, commit_tags={v2026.07.0-rc.01}, state=failed, release_status=COMMIT, discovered 23:27:56. Row 223: commit 143cece86 (committed 22:17:02), same tag, release_status=prerelease, discovered 23:27:57.

What the data rules out and in: a1b58193d was COMMITTED 23:27:56 — LATER than the tag's real target — so there was never an earlier same-named tag at it (the delete/move hypothesis is dead). Both rows registered within ~1 second. The producer is a SAME-WINDOW MIS-ATTRIBUTION in rc.04's discovery: at 23:27:56 it registered the then-latest master commit as release_status=COMMIT and stapled the release tag onto it, one second before registering the tag's actual target. The exact rc.04 line is superseded on master; rune's journal for the 20s window rotated; the DB snapshot is the durable record.

Coverage check against the shipped fixes: the AC#1 write-guard would have REFUSED the mis-attribution at write (rev-parse(tag)=143cece86 ≠ a1b58193d — row 222 never gains the tag); the pruner move-drop HEALS the existing row on its normal cycle. The event sits squarely in the fixed class.
---

author: engineer (relayed by foreman)
created: 2026-07-13 01:34
---
DEV RETRY TRACE CORRECTION (2026-07-13 night, hard dev evidence): the foreman's retry-after-rollback false-green report was WRONG on all three hypotheses — the scheduler behaved correctly end to end. Dev row 331014: scheduled_at 01:22:19 → started_at 01:22:59 → rolled_back_at 01:23:16. RunSchedule's documented terminal-row re-run flipped rolled_back→scheduled (STATBUS-160's trigger only guards state='completed' flips — never fired, correctly); the daemon claimed and RAN the upgrade; "scheduled_at on a rolled_back row" was the leftover of a claim→run→rollback cycle, not a stuck write. The REAL dev blocker is downstream and deterministic: BINARY_REPLACE_FAILED — the procured rc.02 binary fails post-swap self-verify ("procured binary is still reported stale", exit 2, "will fail the same way") on the first TAG-identified upgrade attempt of the night (all successful dev upgrades were commit-identified). Root-cause trace in flight (mis-built artifact vs procurement race vs comparison defect); it gets its own ticket when named. Separate design gap extracted to its own entry: deploy-workflow green means SCHEDULED, not CONVERGED — the daemon's async run can roll back after the workflow exits green.
---
<!-- COMMENTS:END -->
