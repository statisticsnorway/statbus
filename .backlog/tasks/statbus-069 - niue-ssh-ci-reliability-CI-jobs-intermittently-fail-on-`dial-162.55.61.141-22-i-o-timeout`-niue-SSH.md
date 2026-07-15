---
id: STATBUS-069
title: >-
  niue-ssh-ci-reliability: CI jobs intermittently fail on `dial 162.55.61.141:22
  i/o timeout` (niue SSH)
status: To Do
assignee: []
created_date: '2026-06-17 07:59'
updated_date: '2026-07-15 08:12'
labels:
  - tooling
  - not-install-upgrade
dependencies: []
documentation:
  - doc-026 - Self-hosted-GitHub-runner-on-niue-—-design-STATBUS-069.md
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: trustworthy CI — gated jobs must not fail on infrastructure noise.
> BENEFIT: CI stops flapping on SSH timeouts to niue; gated jobs stop failing spuriously.
> HYPOTHESIS (King): crowdsec on niue blocks GitHub's shared-runner IP ranges; operator verifying read-only now; fix direction if confirmed = self-hosted runner on the host via docker compose (King's proven pattern from another project).
> COMPLEXITY: engineer-substantial (build phase shipped — remaining work is the Phase-3 workflow migration).
> DEPENDS ON: nothing.

---

CI jobs that SSH to niue.statbus.org (162.55.61.141) intermittently fail with `dial tcp 162.55.61.141:22: i/o timeout` (30s connect timeout) BEFORE any work runs — a niue SSH reachability/latency issue, NOT a code failure.

WHERE THIS STANDS (2026-07-08): hypothesis CONFIRMED — CrowdSec's community IP blocklist bans hundreds of GitHub Actions runner IPs, causing intermittent SSH drops to niue. Design (doc-026) and Phase 2 are DONE: a self-hosted, repo-scoped ephemeral runner is built, registered, and online on niue (isolated user, no docker socket, own CrowdSec whitelist scoped to its private bridge network only — GitHub's public IP ranges are deliberately NOT whitelisted). Currently in a one-day observation window (through the first weekly refresh) before Phase 3: migrating the actual CI workflows (pg_regress trusted leg, notify-all-clouds, seq/docker-maintenance) onto the runner, per doc-026's migration order. Remaining work on this ticket = Phase 3 only.

CONCRETE INSTANCES (2026-06-17):
- notify-all-clouds.yaml: `notify (statbus_jo)` leg failed on push 55cb5c959 (the other 6 slots succeeded → niue up, single-slot/transient); SUCCEEDED on the next push c3e00f5f4.
- pg_regress.yaml (`Run tests on remote server`): failed on push 73ea5210f — the SSH dial timed out before checkout/tests; Fast Tests (same SQL, different path) PASSED, corroborating code is fine. Manual re-run unblocked it.

IMPACT: each timeout reds a strict CI gate and costs a manual re-run; if it recurs it can gate the rc.04 release gate spuriously. pg_regress runs ON niue via SSH (`git fetch && git checkout <sha> && ./dev.sh continous-integration-test`), so its reliability is coupled to niue SSH reachability.

NOT URGENT (transient, self-recovers on re-run). If the pattern persists, investigate: niue SSH/network load, sshd connection limits, or whether pg_regress should run somewhere less coupled to a production host. Architect flagged the external root cause is real (no-flaky-tests: it's niue SSH dial reliability, not a flaky test). Foreman observed both instances firsthand.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Trace tool pre-staged: engineer authors ops/github-runner/runner-health-trace.sh (read-only capture + explicit --with-disconnect arm) AND the K2 provisioning runbook template; architect reviews bytes; foreman commits — collapses the King's trace step to ONE command
- [ ] #2 [KING — K1, ~2 min] Run the committed trace on niue as root (one command, output pastes to this ticket): captures idle log cadence + the deliberate-disconnect reconnect signature for layer (b) calibration
- [ ] #3 Engineer calibrates the layer-(b) freshness signal from K1's paste; finalizes ops/github-runner/runner-health.sh FINAL BYTES + the exact sshdoers line + the K2 runbook (keygen → printed sshdoers/authorized_keys lines → gh secret set → shred); architect final-bytes review; foreman commits (canonical copy only — NO workflow change yet)
- [ ] #4 [KING — K2, ~5 min, ONE session] Execute the pre-staged runbook on niue: install the script root-owned at /usr/local/sbin/statbus-runner-health (visual diff vs the reviewed commit), ssh-keygen, append the sshdoers + authorized_keys lines, gh secret set RUNNER_HEALTH_SSH_KEY, shred the private key — all bytes final per the STATBUS-167 one-session discipline
- [ ] #5 Engineer re-adds the hosted canary job (self-hosted legs `needs:` it); foreman pushes; ONE PUSH proves the canary green-gating the self-hosted legs — the ticket's canary half closes on that run
- [ ] #6 seq-logserver + docker-maintenance migrations land via STATBUS-191 (engineer-ready, NOT King-gated, may close first); zero public-SSH CI consumers remain
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-06 17:31
---
HYPOTHESIS CONFIRMED (2026-07-06, root inspection authorized by the King). Mechanism found and active: crowdsec on niue subscribes to the community blocklist (CAPI) — 38,822 active ban decisions, 38,821 from the community list, INVISIBLE in the default `cscli decisions list` (which showed zero; they appear only with -a). The community list currently bans hundreds of IPs inside the Azure prefixes GitHub Actions runners use: 399 in 20.x, 206 in 52.x, 72 in 4.x, 67 in 13.x, 64 in 40.x (cross-checked against api.github.com/meta actions ranges). A runner drawing a banned IP is firewall-DROPPED → exactly the observed `dial tcp 162.55.61.141:22: i/o timeout` signature (drop, not refusal), intermittent by IP lottery — the symptom fired again TODAY at 15:33 UTC during the board pushes. Local alert history (24 retained, all ssh brute-force from CN/VN/HK/etc.) contains zero Azure entries — the bans come from the community feed, not local detections, which is why they never showed in local alerts. FIX DIRECTION (King's proven pattern): self-hosted runner ON niue via docker compose — CI traffic never crosses the public SSH gate. Deliberately NOT whitelisting GitHub's ranges in crowdsec: attackers use GitHub runners for SSH attacks (the very reason the community list bans these IPs); a whitelist would re-open that door. COMPLEXITY: engineer-substantial. Buildable when prioritized.
---

author: architect
created: 2026-07-06 19:41
---
DESIGN LANDED → doc-026 (architect, 2026-07-06; DESIGN ONLY — no server writes, no workflow edits, no runner registration). Core decision: the runner is a NETWORK-POSITION fix, not a privilege change — a repo-scoped ephemeral runner (GitHub's official image, own compose project under a new github-runner user, no docker socket, 2cpu/2g caps) moves the SSH CLIENT onto niue so CI never crosses the public gate; the per-slot keys + sshdo allowlists remain the sole authority for what CI may do. Load-bearing security rule (repo verified PUBLIC): no pull_request-triggered job ever carries the self-hosted labels — pg_regress splits into a hosted PR leg (unchanged, fork PRs keep failing harmlessly without secrets) and a self-hosted trusted leg; plus the require-approval-for-all-outside-collaborators repo setting as backstop. Migration order: runner idle → notify-all-clouds (canary) → pg_regress trusted legs → seq/docker-maintenance; rollback = one runs-on line per workflow. Loud-signal preserved: a hosted canary job fails red naming the runner when it is offline (a queued job would otherwise sit silent up to 24h). Explicitly NOT done, recorded so nobody simplifies to it later: whitelisting GitHub's public ranges in crowdsec (King-rejected); the only crowdsec change is whitelisting the private Docker bridge subnet so the runner cannot self-ban — unreachable from the public internet. Prior art: read-only niue inspection found no existing runner (seq is the log server); github-run.sh stays as the allowlist precedent. Awaiting the King's approval before any build.
---

author: foreman
created: 2026-07-08 13:52
---
PHASE 2 DEPLOYED (2026-07-08, King-approved niue root session, foreman-driven per the README runbook, every step verified live): (1) github-runner user created — docker group, NO sudo (uid 1016, groups verified). (2) Four repo artifacts placed in /home/github-runner, owned github-runner. (3) 1h registration token minted via gh api, placed as .env mode 600, local copy destroyed. (4) Image built + container started as github-runner; runner REGISTERED AND ONLINE — container log 'Listening for Jobs', GitHub API shows runner 'niue' online with labels self-hosted,Linux,X64,niue; RUNNER_TOKEN blanked afterward. (5) CrowdSec: new ssb/gha-runner-whitelist (separate file, own identity) whitelisting the gha-runner_default bridge subnet 172.22.0.0/16 — the private RFC1918 bridge only, categorically NOT GitHub's public ranges; crowdsec reloaded, active, parser enabled+local. (6) Weekly refresh installed: upgrade-to-latest-gha-runner.sh → /usr/local/bin, service+timer enabled — next fire Sun 2026-07-12 03:17 UTC. (7) NOW OBSERVING: one day idle including Sunday's first timer pass before any workflow migrates (phase 3 gate per doc-026 §3). The same root session also carries the STATBUS-123 sshdoers durable-entrypoint edit — pending the mechanic's repo artifacts (exact byte-stable script line) landing so the allowlist pins the right bytes.
---

author: foreman
created: 2026-07-12 13:09
---
PHASE-3 GATE MET (operator verification, 2026-07-12): all three observation verdicts GREEN — (a) the weekly refresh timer fired on schedule (runner re-listening at 03:17:07Z, the exact Sunday window) and the service run succeeded; (b) the runner container up 10 hours, registered and online, continuous token refresh through 12:28Z; (c) zero CrowdSec alerts involving the runner's bridge subnet. The one-day observation window including the first timer pass is complete. PHASE 3 (migrating the workflows — pg_regress trusted leg, notify-all-clouds, seq/docker-maintenance — onto the runner per doc-026's migration order) is UNBLOCKED and queued to the engineer behind the STATBUS-163 build. Post-migration reminders recorded elsewhere: STATBUS-162's capture pipeline retires on the pg_regress move (named condition on that ticket).
---

author: foreman
created: 2026-07-12 18:05
---
KING APPROVED the SSH-key health-probe canary design (2026-07-12 evening). The design, in full, so this ticket stands alone:

PROBLEM: a job targeting an offline self-hosted runner queues silently for up to 24h. We need a loud red on the next push when the runner is down. The first attempt (a hosted job asking GitHub's API) needed a personal access token — withdrawn: a standing GitHub credential is the wrong price for a liveness bit.

APPROVED DESIGN: a hosted canary job SSHes to niue with a DEDICATED probe key and runs ONE allowlisted command; notify's self-hosted legs `needs:` it, so a red canary SKIPS them instead of queueing.

1. IDENTITY: new keypair minted only for this. Public half → the github-runner account's authorized_keys on niue; private half → repo secret RUNNER_HEALTH_SSH_KEY (same custody class as the deploy key). Revocable server-side any time; no expiry lifecycle; no personal token.
2. AUTHORIZATION: one sshdo allowlist line — `github-runner: /usr/local/sbin/statbus-runner-health` — that key can run exactly that command, nothing else.
3. THE PROBED COMMAND is a ROOT-PROVISIONED, SELF-CONTAINED script (architect custody ruling): because github-runner has docker access (root-equivalent on the shared box), the script must NOT come from a git checkout — otherwise anyone with master-push could execute arbitrary privileged commands through it. The King installs it root-owned at /usr/local/sbin/statbus-runner-health from the reviewable canonical copy ops/github-runner/runner-health.sh — the same way sshdo/sshdoers themselves are managed. Self-contained (docker + shell builtins only) so nothing on the box needs keeping current.
4. THE PROBE CHECKS two layers: (a) the runner container is running; (b) the runner's GitHub session is fresh — the freshness signal is being CALIBRATED from a live capture of the runner's real log behavior (idle cadence + a deliberate disconnect), never guessed.
5. RESIDUALS, named: a runner locally green but dropped by GitHub can fake (b) — bounded by the notify legs failing loudly on the next push; the hosted canary crosses the public SSH gate, so crowdsec can occasionally ban it → one false-red push, self-correcting.

ROLLOUT ORDER (the STATBUS-167 discipline): the King provisions all three artifacts in ONE session (script, sshdoers line, key) with the FINAL calibrated bytes — only then does the workflow re-add the canary job. Design ratified in doc-026 delta 9 v4 (commit f560bdd1d). Remaining sequence: King's trace capture → engineer calibrates layer (b) → architect reviews final bytes → King's one-session provisioning → workflow re-add.
---

author: architect
created: 2026-07-13 09:05
---
BOARD TRIAGE (architect, 2026-07-13) — REMAINING SCOPE made exact (the description's 'remaining work is the Phase-3 workflow migration' is stale — the migration is mostly SHIPPED: notify, pg_regress, and all 7 deploy-to-* slot workflows carry self-hosted today, grep-verified). What actually remains: (1) CANARY PART 2 — the King's runner trace capture (runner-health-trace.sh) → engineer calibrates layer (b) → final script bytes reviewed → the ONE-SESSION three-artifact provisioning (root-owned script + sshdoers line + RUNNER_HEALTH_SSH_KEY) → workflow re-adds the runner-online canary; (2) the seq-logserver + docker-maintenance workflow migrations (the last two SSH consumers). Ticket closes when both land and one push proves the canary green-gating.
---

author: architect
created: 2026-07-15 08:12
---
REMAINING-069 CONCRETE PLAN (architect, 2026-07-15, on the King's prod; the design is DONE — doc-026 + comments #5/#6 — this is the execution sequence as checkable entries, now the ACs above). THE KING'S INVOLVEMENT IS COLLAPSED TO TWO TOUCHPOINTS, both running PRE-STAGED, PRE-REVIEWED bytes:

K1 (~2 minutes): one command — the committed runner-health-trace.sh — paste the output here. The trace is read-only except its explicit --with-disconnect arm (a brief docker stop/start of the runner container to capture the reconnect signature layer (b) needs). Custody note: running a one-time trace from the git checkout is fine — the King reads what he runs and he is the human in control; the ROOT-PROVISIONED custody rule applies to the STANDING probed command (executed unattended by CI), which is exactly why K2 installs that one root-owned from reviewed bytes.
K2 (~5 minutes, one session): execute the pre-staged runbook — install the reviewed script root-owned, keygen, the two printed lines (sshdoers + authorized_keys, pubkey filled from the keygen output), gh secret set, shred. Nothing is composed in-session; every byte was reviewed and committed beforehand (167 discipline).

OWNER SEQUENCE (matching the ACs): S1 engineer pre-stages trace+runbook → S2 architect bytes review → S3 foreman commit → S4 [KING K1] → S5 engineer calibrates + finalizes script/sshdoers/runbook → S6 architect final-bytes review (contract: exit 0 healthy / nonzero naming the failed layer; self-contained docker+builtins only — the cold-agent test) → S7 foreman commit → S8 [KING K2] → S9 engineer re-adds the canary, foreman pushes → S10 the next push IS the oracle (canary green, self-hosted legs gated).

WORKSTREAM 2 SPLIT OUT: seq-logserver + docker-maintenance → STATBUS-191 (engineer, not King-gated, closes independently — ship-bit-by-bit). 069 closes when the canary chain's one-push proof lands AND 191 is done (final AC).

Sequencing note for the foreman's drive: S1-S3 start NOW (no gate); K1 is the first King touchpoint and everything up to S3 exists purely to make it a two-minute ask.
---
<!-- COMMENTS:END -->
