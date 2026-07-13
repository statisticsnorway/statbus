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
