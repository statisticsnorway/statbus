---
id: STATBUS-120
title: >-
  notify-ci-fail: 'Notify cloud services' job fails on master push (statbus_jo
  upgrade check exits 1)
status: To Do
assignee:
  - operator
created_date: '2026-07-02 17:01'
labels:
  - ci
  - notify
  - investigation
dependencies: []
ordinal: 120000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On every master push, the Images/notify workflow's `notify (statbus_jo)` job fails. It SSHes (appleboy/drone-ssh v1.8.0) to cloud server statbus_jo and runs that server's own installed `./sb upgrade check`, which exits 1 ("Process exited with status 1"). Observed on run 28601676453 (push 1563e6887, 2026-07-02); pre-existing, NOT introduced by the seed/guardrail change (that change touches no upgrade/notify code and deploys nothing).

This is a real red on master pushes — investigate the root cause, don't dismiss as flaky.

Questions to answer:
1. Is statbus_jo reachable over SSH from CI / at all? (Is the server up?)
2. When you run `./sb upgrade check` on statbus_jo yourself (SSH read/diagnostic), what is the actual error + exit code? Why does it fail?
3. Is this failing on EVERY recent master push, or intermittent? (Check the last several 'Notify cloud services' runs.)
4. Is statbus_jo a live slot that SHOULD be getting upgrade notifications, or a stale/decommissioned target whose notify entry should be removed?
5. Classify: real problem (a cloud server's upgrade-notify is broken -> fix path) vs benign/misconfigured (-> config cleanup).

Constraints: DIAGNOSTICS ONLY. SSH reads are fine; NO writes to any server, NO DB writes, NO deploys. Report findings to the foreman with the concrete error + a recommended fix (do not implement without foreman/King go-ahead).
<!-- SECTION:DESCRIPTION:END -->
