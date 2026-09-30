---
id: STATBUS-435
title: Define when installed release metadata supersedes a newer failed upgrade
status: To Do
assignee: []
created_date: '2026-09-29 21:23'
updated_date: '2026-09-30 12:30'
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
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Owner decision on tier-first versus newer-version supersession is recorded against the actual older-A/newer-B chronology
- [ ] #2 The chosen behaviour is implemented and pg_regress covers stable-classified installed A versus newer failed B and equal-tier ordering; use a forward migration only if shipped SQL semantics change
- [ ] #3 The two arcs control or assert the discovery/enrichment outcome and give the intended verdict independently of live GitHub discovery success; record the limits of the existing Hetzner comparison evidence
<!-- AC:END -->
