---
id: STATBUS-123
title: >-
  notify-ci-fail: 'Notify cloud services' job fails on master push (statbus_jo
  upgrade check exits 1)
status: In Progress
assignee:
  - operator
created_date: '2026-07-02 17:01'
updated_date: '2026-07-11 20:22'
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

author: architect
created: 2026-07-08 13:49
---
DURABLE-ENTRYPOINT DESIGN (architect, 2026-07-08 — King folded the fix here: the byte-patch is DEAD; this ships in the same niue root session as runner phase 2, doc-026). The fragility being killed: /etc/sshdoers pins the EXACT BYTES of the workflow's script block, so every future edit to that block silently re-breaks notify (the discover→check rename proved it: green 15:45, red 15:47, comment #2). The durable shape moves the CONTENT into the repo and leaves only a never-changing INVOCATION LINE in the allowlist.

THREE ARTIFACTS, deliberately minimal:
1. REPO: `ops/ci-notify.sh` (committed, executable, ~5 lines): `#!/bin/sh` + `cd "$(dirname "$0")/.."` + `[ -x ./sb ] || exit 0` + `exec ./sb upgrade check`. Content evolves via normal git deploys — never touches the allowlist again.
2. REPO: `.github/workflows/notify-all-clouds.yaml` script block becomes the single byte-stable line `~/statbus/ops/ci-notify.sh` (nothing else — no ifs, no cd; those live server-side in the script). This is the ONLY string sshdo ever sees again.
3. NIUE (root, one visit, rides the runner-phase-2 session): edit the 8 statbus_* entries in /etc/sshdoers to allowlist exactly that one line, replacing the old pinned script bytes. Keep a repo-side reference copy of the edited entries (ops/niue-sshdoers.reference — documentation, not deployment; niue's file stays hand-managed as today).

TRUST BOUNDARY, stated honestly (so the King rules with eyes open): allowlisting a path inside the slot user's own checkout means the checkout's content decides what runs — but that is the SAME trust anchor as today (the old allowlisted bytes ran `./sb upgrade check`, also repo-delivered code executing as the slot user). What sshdo protects — the CI key cannot run arbitrary commands, only the one pinned invocation — holds unchanged. No privilege change, no new surface.

SEQUENCING: artifacts 1+2 can land on master BEFORE the niue visit (the notify job stays red until the sshdoers edit — no worse than today's 100%-red); the root session then makes it green in one edit. ORACLE: the next master push's notify-all-clouds run — all 7 slots green. FUTURE-PROOF: behavior changes edit ops/ci-notify.sh (repo review + normal deploy); the workflow line and the sshdoers entries never change again. Session budget: one file edit (8 same-shape line replacements) — does not grow the visit.
---

author: foreman
created: 2026-07-08 13:56
---
DURABLE ENTRYPOINT DEPLOYED, both halves (2026-07-08, same King-approved root session as the runner phase 2): REPO half c07439b5b — new ops/ci-notify.sh (4 lines, behavior evolves via git) + the workflow script block reduced to the single byte-stable line `~/statbus/ops/ci-notify.sh` (od-verified). SERVER half — /etc/sshdoers: all 8 notify entries replaced with that single pinned line (old multi-line <binary>-escaped pins removed), comment block updated to stay true, backup at /etc/sshdoers.bak-20260708-statbus123, cat -A verified no trailing whitespace; the pg_regress and deploy entries untouched; local reference copy tmp/niue-sshdoers refreshed from the live file. DISCLOSURE from the live read: the file had ALREADY been hand-patched discover→check sometime after comment #2's diagnosis (it no longer matched our stale local copy) — presumably the King's own edit; yesterday's notify run still failed, consistent with the dial-lottery reds (STATBUS-069) rather than the allowlist. ORACLE STATUS: the 13:54 run (28948097390) fired with the new workflow BEFORE the allowlist edit landed — red as expected. Green now requires each slot to have ops/ci-notify.sh in its checkout (arrives with each slot's next upgrade); the byte-pinning failure CLASS is ended — future workflow-behavior changes edit the script via git, never the server. Full immunity from the dial-lottery reds comes when phase 3 moves notify onto the niue runner (069, after the observation day).
---

author: foreman
created: 2026-07-11 20:22
---
STATUS SYNC (foreman, 2026-07-11), honest correction to the overnight theory: 'Notify cloud services' is STILL FAILING on every master push — latest three: run 29077265816 (6ac199afc, 2026-07-10), 29016872841 (b14e23dc4, 2026-07-09), 28989777186 (653834672, 2026-07-09). The 2026-07-08 niue session deployed the sshdoers durable entrypoint (all 8 notify entries → ~/statbus/ops/ci-notify.sh) and the repo carries ops/ci-notify.sh + the single-line workflow (c07439b5b) — the expectation was 'greens as slots pull ci-notify.sh', which has NOT happened: slots only update their checkouts on DEPLOY, and no slot has deployed since, so ~/statbus/ops/ci-notify.sh likely does not exist yet on most slots — the sshdoers entry points at a file the slot hasn't pulled. NEXT STEP when picked up: operator reads one failing slot (does ~/statbus/ops/ci-notify.sh exist? what does the loud sshdo rejection now say — the 128 fix means the failure is finally NAMED in the CI log, read it first); the likely fix is either deploying the slots or a bootstrap shim, architect-ruled. Queued behind the 154/wave-8 closure.
---
<!-- COMMENTS:END -->
