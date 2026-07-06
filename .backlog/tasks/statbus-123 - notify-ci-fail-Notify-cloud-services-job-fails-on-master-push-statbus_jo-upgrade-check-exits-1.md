---
id: STATBUS-123
title: >-
  notify-ci-fail: 'Notify cloud services' job fails on master push (statbus_jo
  upgrade check exits 1)
status: In Progress
assignee:
  - operator
created_date: '2026-07-02 17:01'
updated_date: '2026-07-02 17:50'
labels:
  - ci
  - notify
  - investigation
dependencies: []
ordinal: 123000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a master push notifies every cloud box, and a red notify job means something real.
> BENEFIT: the post-push upgrade poke reaches all 7 cloud slots again, and the 100%-red job stops training everyone to ignore CI failures on every single push.
> STAGE: Ops (Stage 2 support).
> COMPLEXITY: operator-simple — one King-approved line-edit in /etc/sshdoers on niue (discover→check in the 8 statbus_* entries) + a workflow re-run as the oracle.
> DEPENDS ON: the King's nod (server write); pairs with STATBUS-128 (same server session) — soft, not a hard dependency.

---

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

author: foreman
created: 2026-07-02 17:50
---
ROOT CAUSE CONFIRMED (operator deep-dive with root read access; foreman-verified reasoning chain, 2026-07-02 ~17:50). The CI key in every statbus_* slot's authorized_keys on niue is FORCED through command="/usr/local/bin/sshdo" (a command allowlist). /etc/sshdoers (managed by hand; local copy tmp/niue-sshdoers, lines 31-38) whitelists the EXACT OLD script bytes containing `./sb upgrade discover`. Commit 8c0631ee9 (2026-06-18) renamed discover→check and updated the workflow — but not the server allowlist → sshdo rejects the new script SILENTLY (exit 1, zero output). TIMELINE MATCHES EXACTLY: last green run 2026-06-18T15:45 (4076fe1d4), first red 15:47 (8c0631ee9, the rename). Operator's earlier manual-SSH successes used his unrestricted personal key — the initial 'drone-ssh buffering' hypothesis is RETIRED. FIX (root write on niue — HELD FOR THE KING per no-writes-without-approval): edit /etc/sshdoers, replace `./sb upgrade discover` → `./sb upgrade check` in the 8 statbus_* entries; update the repo-side copy tmp/niue-sshdoers to match; re-run the notify workflow as the oracle. FRAGILITY NOTE for a follow-up decision: the allowlist pins exact script BYTES, so ANY future edit to the workflow's script block silently re-breaks notify — durable options (allowlist a stable server-side entrypoint, or manage /etc/sshdoers from the repo) worth a separate task.
---
<!-- COMMENTS:END -->
