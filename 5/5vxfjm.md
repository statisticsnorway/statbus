---
id: 5vxfjm
title: "Prototype: an import job writes as its user's role"
state: "doing"
type: spike
priority: ""
assignee: ["buffalo"]
labels: []
group: ""
rank: "zzzzq"
created: 2026-11-21
updated: 2026-11-21
doing_since: "2026-11-21T09:49"
stage: "active"
model: "claude-opus-4"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
Show on a branch whether the worker can run an import job's writes as the job user's role, so DEFAULT auth.uid() stamps the real writer.

## Purpose
sql_saga's provenance proposal (k5q120 notes, 2026-11-20) fills edit_by_user_id from the column DEFAULT on every changed piece. The worker runs imports as postgres, where auth.uid() is NULL and edit_by_user_id is NOT NULL, so every import would fail. If this cannot work, the sql_saga work needs another StatBus answer before it is worth finishing.

## Principle
Prototype before building: a branch, real imports, observed results; no merge to master from this task.

## Relevant details
Plan: (1) Branch prototype/import-as-user-role. (2) In the worker's import task, SET LOCAL ROLE "<job user email>" before each analyse/process batch and RESET ROLE before the worker's own bookkeeping (worker.tasks, import_job state, base_change_log), all in one transaction. Prove first in a psql script: BEGIN; SET LOCAL ROLE user; INSERT ...; RESET ROLE; UPDATE worker.tasks ...; SET LOCAL ROLE user; ...; COMMIT works, and a later statement after RESET ROLE runs as postgres again. (3) Run a full Norway sample import (samples/norway, the getting-started set and a legal unit + establishment file) as rabbit-review@statbus.org (regular user) and as an admin user. (4) Record every refusal: steps needing rights a regular user lacks (DDL on the job data table, writes to statistical_unit, worker.*, import.* temp tables). For each, decide: SECURITY DEFINER for that step, or run it with the role reset. (5) Check edit_by_user_id on every written row equals the job user, with set_import_job_user_context and the explicit edit_by_user_id in import.analyse_edit_info removed. (6) Measure the import time against master on the same sample. (7) Write the result in this task: works / works with N definer steps / does not work, and why. Fallback if not: auth.uid() falls back to a protected session context for the acting user.

## Depends on

## Acceptance
- [x] A psql script on the branch shows SET LOCAL ROLE and RESET ROLE inside one transaction: rows written under the role carry the job user, statements after RESET ROLE run as postgres, and COMMIT keeps both
- [x] A full Norway sample import runs as rabbit-review@statbus.org with every written unit row stamped with that user, or the task lists each step that is refused and why
- [x] Import time on the branch compared with master on the same sample, recorded here
- [ ] [Owner] Reads the result (works, works with listed definer steps, or does not work) and decides whether to build it; the decision is recorded in this task's notes

## Notes


RESULT 2026-11-21 (buffalo): WORKS, 0 definer steps. Branch prototype/import-as-user-role (f4aedb8cf), artifacts prototype/5vxfjm/. Patch: admin.import_job_process wraps import_job_analysis_phase and import_job_processing_phase in set_config('role', <job user email>, true) ... RESET ROLE; set_import_job_user_context call removed; analyse_edit_info stamps auth.uid() instead of job.user_id. Bookkeeping (import_job state, data-table DDL in prepare, ANALYZE, batch_seq, worker.tasks, base_change_log via process_tasks) stays as postgres. Full BRREG selection (4924 LU + 24027 ES, after getting-started) as rabbit-review@statbus.org (regular_user): no refusals; every row in enterprise/legal_unit/establishment/external_ident/location/activity/contact/stat_for_unit stamped rabbit-review; a statement trigger confirmed current_user=rabbit-review and auth.uid()=its id during writes. Why no refusals: regular_user already has DML on unit tables and the job data table; derivation runs in separate worker tasks as postgres. Timing (same sample, fresh DBs from statbus_test_template): branch 81.4s/72.9s, master 72.4s/74.2s, no measurable difference. CAVEAT: SET LOCAL ROLE is not a security boundary here: session_user is postgres, so code under the role can RESET ROLE / SET ROLE postgres / SET SESSION AUTHORIZATION (step1.log). It gives correct stamping and RLS, not containment of import procedures. Admin-user comparison run not done (master run used the same regular user).
check 1: prototype/5vxfjm/step1.log: stamped rabbit-review under role, postgres after RESET ROLE, both rows after COMMIT
check 2: BRREG selection import as rabbit-review, 0 refusals, all unit rows stamped rabbit-review (branch-stamps.log)
check 3: branch 81.4s/72.9s vs master 72.4s/74.2s
## History
- 2026-11-21T09:49 todo -> doing/active (take)
