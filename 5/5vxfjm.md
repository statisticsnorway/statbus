---
id: 5vxfjm
title: "An import job writes as its user's role"
state: "doing"
type: spike
priority: ""
assignee: ["hibiscus"]
labels: []
group: ""
rank: "zzzzq"
created: 2026-11-21
updated: 2026-11-21
doing_since: "2026-11-21T09:49"
stage: "waiting"
model: "claude-opus-4"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
waiting_on: "a free slot of its own (statbus_a or statbus_b) to build it on master, independent of the map work; owner request 1, 2026-11-27"
waiting_since: "2026-11-27T11:07"
waiting_asked_by: "hibiscus"
---

## Goal
Import jobs write their unit rows as the job user's role, so auth.uid() stamps the real writer, on master.

## Purpose
sql_saga's provenance proposal (k5q120 notes, 2026-11-20) fills edit_by_user_id from the column DEFAULT on every changed piece. The worker runs imports as postgres, where auth.uid() is NULL and edit_by_user_id is NOT NULL, so every import would fail. If this cannot work, the sql_saga work needs another StatBus answer before it is worth finishing.

## Principle
Import writes run as the job user's role so stamping and RLS are the user's; SET LOCAL ROLE is not containment (session_user stays postgres), and the code says so where the role is set.

## Relevant details
Owner 2026-11-27 (request 1): build it on master in a slot of its own, statbus_a or statbus_b whichever is free, independent of the map work; base: prototype branch prototype/import-as-user-role f4aedb8cf. If it works, commit and push; if not, the problem is recorded here.

## Depends on

## Acceptance
- [x] A psql script on the branch shows SET LOCAL ROLE and RESET ROLE inside one transaction: rows written under the role carry the job user, statements after RESET ROLE run as postgres, and COMMIT keeps both
- [x] A full Norway sample import runs as rabbit-review@statbus.org with every written unit row stamped with that user, or the task lists each step that is refused and why
- [x] Import time on the branch compared with master on the same sample, recorded here
- [x] [Owner] Reads the result (works, works with listed definer steps, or does not work) and decides whether to build it; the decision is recorded in this task's notes
- [ ] A migration on master makes admin.import_job_process run the analysis and processing phases as the job user's role (as prototype f4aedb8cf), removes set_import_job_user_context, and analyse_edit_info stamps auth.uid(); a SQL test fails on master before it and passes after: rows an import writes carry the job user's id
- [ ] ~~A full Norway sample import as a regular user and as an admin user stamps every written unit row with that user, with no refusals; import time compared with master on the same sample and recorded here~~ (not relevant: Restated with its baseline as check 9 (task review 2026-11-27), hibiscus, 2026-11-27)
- [ ] ~~Committed and pushed to master with CI green on its commit, or the failure that stopped it recorded in this task's notes~~ (not relevant: Restated as one done condition (task review 2026-11-27), hibiscus, 2026-11-27)
- [ ] Committed and pushed to master with CI green on that commit

## Requests
- 2026-11-27T11:06 request 1 by jhf:
  When either Statbus A or Statbus B is available, maybe this one could be scheduled independently in the master branch there. And if it works out, we can commit and push. If not, we will know what the problem is all recorded in this ticket
  resolved 2026-11-27T11:07 by hibiscus:
    Check 4 ticked with the owner's decision (build it). Title and goal now say build, on master; principle: in statbus_a or statbus_b, whichever is free, independent of the map work, prototype f4aedb8cf as base, the role is stamping and RLS, not containment. New checks 5 (migration with a red-then-green SQL test), 6 (Norway import as regular and admin user, timing), 8 (committed and pushed to master, CI green). Waits on a free slot; the z2qt08 wait is gone.

## Notes


RESULT 2026-11-21 (buffalo): WORKS, 0 definer steps. Branch prototype/import-as-user-role (f4aedb8cf), artifacts prototype/5vxfjm/. Patch: admin.import_job_process wraps import_job_analysis_phase and import_job_processing_phase in set_config('role', <job user email>, true) ... RESET ROLE; set_import_job_user_context call removed; analyse_edit_info stamps auth.uid() instead of job.user_id. Bookkeeping (import_job state, data-table DDL in prepare, ANALYZE, batch_seq, worker.tasks, base_change_log via process_tasks) stays as postgres. Full BRREG selection (4924 LU + 24027 ES, after getting-started) as rabbit-review@statbus.org (regular_user): no refusals; every row in enterprise/legal_unit/establishment/external_ident/location/activity/contact/stat_for_unit stamped rabbit-review; a statement trigger confirmed current_user=rabbit-review and auth.uid()=its id during writes. Why no refusals: regular_user already has DML on unit tables and the job data table; derivation runs in separate worker tasks as postgres. Timing (same sample, fresh DBs from statbus_test_template): branch 81.4s/72.9s, master 72.4s/74.2s, no measurable difference. CAVEAT: SET LOCAL ROLE is not a security boundary here: session_user is postgres, so code under the role can RESET ROLE / SET ROLE postgres / SET SESSION AUTHORIZATION (step1.log). It gives correct stamping and RLS, not containment of import procedures. Admin-user comparison run not done (master run used the same regular user).
check 1: prototype/5vxfjm/step1.log: stamped rabbit-review under role, postgres after RESET ROLE, both rows after COMMIT
check 2: BRREG selection import as rabbit-review, 0 refusals, all unit rows stamped rabbit-review (branch-stamps.log)
check 3: branch 81.4s/72.9s vs master 72.4s/74.2s
2026-11-21 19:24 (Rabbit, coordinator) reviewed buffalo's result: branch prototype/import-as-user-role f4aedb8cf pushed, not merged; artifacts tmp/5vxfjm/ (role-probe.sql, patch.sql, branch-run*/master-run* logs, check-stamps.sql). Owner informed; the sql_saga agent (f86twg) is starting the provenance work on that basis. Open for the owner: build or not; admin-user comparison run not done.
2026-11-22 22:23 still with hibiscus, parked: units on a map (z2qt08) came first by the owner's order; this prototype resumes after z2qt08's phases land.
check 4: Owner 2026-11-27 11:06 (request 1): build it. 'When either Statbus A or Statbus B is available, maybe this one could be scheduled independently in the master branch there. And if it works out, we can commit and push. If not, we will know what the problem is all recorded in this ticket.'
## History
- 2026-11-21T09:49 todo -> doing/active (take)
- 2026-11-21T20:10 handed to hibiscus: buffalo's session ended (closed 2026-11-21 10:29)
- 2026-11-23T12:14 doing/active -> doing/waiting (wait)
- 2026-11-27T11:06 request 1 by jhf
- 2026-11-27T11:06 request 1 delivered to hibiscus (session_hibiscus_1793348926173_ffff8733f4ad20e1)
- 2026-11-27T11:07 request 1 acknowledged by hibiscus
- 2026-11-27T11:07 request 1 in progress by hibiscus: hug task check 5vxfjm 4 "Owner 2026-11-27 11:06 (request 1): build it. 'When either Statbus A or Statbus B is available, maybe this one could be…"
- 2026-11-27T11:07 resolved request 1 by hibiscus
