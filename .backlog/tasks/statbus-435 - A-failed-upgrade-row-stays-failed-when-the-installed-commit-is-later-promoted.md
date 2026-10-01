---
id: STATBUS-435
title: Define when installed release metadata supersedes a newer failed upgrade
status: To Do
assignee: []
created_date: '2026-09-29 21:23'
updated_date: '2026-10-01 13:26'
labels:
  - upgrade
dependencies: []
priority: high
ordinal: 384200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the LXD arc run (STATBUS-425 M3b; durable evidence on ci/lxd-arcs at test/install-recovery/lxd/evidence/v2026.09.3-rc.17/). Arcs rollback-pair-terminal and restore-broke-reattempt expect their deliberately failed upgrade row B to stay 'failed'. The LXD ledger instead records 'superseded' after an installer rerun, with the checkout still at A.

Both A and B are Git commits. A=ebe058af was committed on 29 September at 00:30:59 UTC and has both v2026.09.3-rc.17 and v2026.09.3 tags. The owner promoted stable around 07:14 UTC. The test created B=29986056 at 14:40:27 UTC, after promotion; B has no RC or stable tag. The ledger records A as release_status='release' and B as release_status='commit', with B superseded at 14:49:52 UTC. Promotion did not happen between B's creation and failure, and no newer fixing version was installed in this observed sequence.

The database's release_status is recognized release metadata, not the Git object type. upgrade_supersede_older ranks that classification before version/date and includes 'failed' rows. Thus older installed stable A outranks newer untagged B. This is observed product behaviour; whether it violates the intended contract is an owner decision, not a proven defect from the red assertions alone. The row is retained with a changed state, not deleted.

Evidence correction from independent review tmp/review-425-m3b.md: 21 failed tag fetches appear across eight Hetzner jobs in 36509925405. The two disputed arcs have no daemon journal/discovery output in that run or rerun 36578946172/artifacts. Failed discovery leaving A classified 'commit' in those two arcs is an inference, not a captured observation. cross-version-rename-handoff recorded successful discovery. Do not claim every Hetzner VM failed authentication.

The contract question is whether installed higher-tier release metadata may supersede a newer lower-tier failed attempt, or supersession requires a newer version. Owner agreement that newly installed fixing code resolves an earlier failure does not by itself settle this older-A/newer-B sequence. No change to the procedure or either assertion has been approved.

**Conditional owner ruling, 2026-10-01 12:24 UTC** (approved in principle, conditional on the presentation matching the details): three facts must not be conflated. (1) What B IS — release_status enrichment when an untagged commit later becomes an RC/release is fine metadata refresh. (2) What HAPPENED to B — it failed; that historical fact is never rewritten. (3) What SUPERSEDES B — only a genuinely newer version that actually gets installed; "the already-installed A is tagged and B is not" is never supersession. A failed row stays failed until something newer succeeds, including B itself succeeding on retry after promotion. Under this rule the arcs' failed-stays-failed assertions are correct and today's tier-first ranking is the bug.

**Owner ruling, 2026-10-01 13:24 UTC (final, supersedes the conditional sketch above): option (i) — supersede at SCHEDULE time, but version-first.** Reasoning: if the only thing you can upgrade to is failing, that is a problem and must stay visible; but once new code is released that replaces the failed attempt, hiding the old failure visually is correct — the row is retained (superseded, never deleted) and inspectable in history, and the operator can run the new upgrade without being stuck on the old failure. Concretely:

1. Supersession requires a strictly NEWER version/chronology (version key, else committed_at), compared ACROSS tiers — release_status never ranks anything.
2. It fires at schedule/registration time of the newer candidate, including over 'failed' rows (that is the visual-hide the owner approved).
3. An older installed release NEVER supersedes a newer failed row (the arc observation — older A superseding newer failed B — remains a bug under this rule and is what the fix removes).
4. release_status stays pure metadata; enrichment when a commit later becomes an RC/release is fine.
5. The arcs' failed-stays-failed assertions are correct for sequences where nothing newer has been scheduled, and must be updated only where they assert failed-survives-a-newer-schedule.

This is shipped SQL semantics: forward migration only, with pg_regress covering installed-release-A vs newer-failed-RC-B (B survives) and newer-C-scheduled supersedes failed B.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Owner decision recorded (2026-10-01 13:24 UTC): supersede at schedule time, strictly newer version across tiers, release_status never ranks, failed rows superseded only by a newer scheduled candidate, rows retained
- [ ] #2 upgrade_supersede_older drops the tier term and orders purely by (version key, committed_at); forward migration only (shipped SQL); pg_regress covers installed-release-A vs newer-failed-RC-B (B survives), newer-C-scheduled supersedes failed B, and equal-version ordering
- [ ] #3 The two arcs control or assert the discovery/enrichment outcome and give the intended verdict independently of live GitHub discovery success; record the limits of the existing Hetzner comparison evidence; assertions match the ruling (failed survives when nothing newer is scheduled)
<!-- AC:END -->
