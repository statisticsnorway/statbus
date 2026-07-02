---
id: STATBUS-123
title: >-
  notify-ci-fail: 'Notify cloud services' job fails on master push (statbus_jo
  upgrade check exits 1)
status: To Do
assignee:
  - operator
created_date: '2026-07-02 17:01'
updated_date: '2026-07-02 17:07'
labels:
  - ci
  - notify
  - investigation
dependencies: []
ordinal: 123000
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

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-02 17:07
---
REFINED ROOT CAUSE (foreman, 2026-07-02) — NOT statbus_jo-specific. The latest notify-all-clouds run (28601676453) fails for ALL 7 matrix servers uniformly: notify (statbus_dev / demo / tcc / ug / ma / et / jo) = ALL failure. Config: .github/workflows/notify-all-clouds.yaml uses appleboy/ssh-action@v1.2.0, host=niue.statbus.org, username=${{matrix.server}}, key=${{secrets.SSH_KEY}}, script `if [ -x ./sb ]; then ./sb upgrade check`. Uniform all-server failure + 'Process exited with status 1' + NO command output in logs => the SSH connection/AUTH fails BEFORE the script runs — i.e. the SHARED path is broken: secrets.SSH_KEY (invalid/expired/wrong-format for the statbus_* users) OR appleboy/ssh-action@v1.2.0 OR niue SSH-from-CI reachability. The operator's 'statbus_jo ./sb upgrade check works (exit 0)' test used the operator's OWN login key, NOT secrets.SSH_KEY, so it did NOT exercise the failing auth path — red herring; the command is fine, the auth is not. IMPACT: the post-push 'check for upgrades' poke reaches NO cloud server; NON-BLOCKING (actual deploys go via the separate deploy-* workflows) but a real 100%-failing job on every master push = noise. RECOMMENDED FIX (needs King — touches CI + secrets): (a) cheap first try = bump appleboy/ssh-action@v1.2.0 -> latest, push, observe the notify run; (b) if still red it's secrets.SSH_KEY — King re-checks/rotates the key's validity for the statbus_* users on niue (foreman cannot see secrets). Do NOT blind-bump the action without King go-ahead. Status stays To Do pending that decision.
---
<!-- COMMENTS:END -->
