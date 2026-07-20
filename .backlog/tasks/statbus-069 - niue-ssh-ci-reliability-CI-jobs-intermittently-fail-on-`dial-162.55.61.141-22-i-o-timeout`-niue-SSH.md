---
id: STATBUS-069
title: >-
  niue-ssh-ci-reliability: CI jobs intermittently fail on `dial 162.55.61.141:22
  i/o timeout` (niue SSH)
status: In Progress
assignee: []
created_date: '2026-06-17 07:59'
updated_date: '2026-07-20 12:47'
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
> ROOT CAUSE (confirmed 2026-07-06): CrowdSec's community blocklist on niue bans hundreds of GitHub-runner IPs; a runner drawing a banned IP is firewall-dropped — the `dial tcp 162.55.61.141:22: i/o timeout` signature. Details in comment #1.
> FIX (doc-026, shipped in phases): a self-hosted, repo-scoped ephemeral runner ON niue moves the SSH client onto the host, so CI never crosses the public gate. Runner built, registered, observed stable (comments #2-#4). Workflow migrations SHIPPED: notify, pg_regress trusted leg, all 7 deploy-to-* slots, and (via STATBUS-191, commit e26d9b6c5) seq-logserver + docker-maintenance — zero public-SSH CI consumers remain.
> REMAINING WORK = the runner-health CANARY ONLY (design King-approved, comment #5): a hosted canary job probes the runner over SSH with a dedicated key + one allowlisted root-provisioned command; self-hosted legs `needs:` it, so an offline runner reds the push instead of queueing silently for 24h.
> EXECUTION PLAN: the six ACs below, sequenced, owner per step (comment #7). The King's involvement is collapsed to two pre-staged touchpoints: K1 (~2 min, one trace command) and K2 (~5 min, one provisioning session). Steps S1-S3 (trace tool + runbook, review, commit) have no gate and can start immediately.
> CLOSES WHEN: one push proves the canary green-gating the self-hosted legs (AC#5) — AC#6 (the migration tail) is already done.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Trace tool pre-staged: engineer authors ops/github-runner/runner-health-trace.sh (read-only capture + explicit --with-disconnect arm) AND the K2 provisioning runbook template; architect reviews bytes; foreman commits — collapses the King's trace step to ONE command
- [x] #2 [KING — K1, ~2 min] Run the committed trace on niue as root (one command, output pastes to this ticket): captures idle log cadence + the deliberate-disconnect reconnect signature for layer (b) calibration
- [x] #3 Engineer calibrates the layer-(b) freshness signal from K1's paste; finalizes ops/github-runner/runner-health.sh FINAL BYTES + the exact sshdoers line + the K2 runbook (keygen → printed sshdoers/authorized_keys lines → gh secret set → shred); architect final-bytes review; foreman commits (canonical copy only — NO workflow change yet)
- [x] #4 [KING — K2, ~5 min, ONE session] Execute the pre-staged runbook on niue: install the script root-owned at /usr/local/sbin/statbus-runner-health (visual diff vs the reviewed commit), ssh-keygen, append the sshdoers + authorized_keys lines, gh secret set RUNNER_HEALTH_SSH_KEY, shred the private key — all bytes final per the STATBUS-167 one-session discipline
- [ ] #5 Engineer re-adds the hosted canary job (self-hosted legs `needs:` it); foreman pushes; ONE PUSH proves the canary green-gating the self-hosted legs — the ticket's canary half closes on that run
- [x] #6 seq-logserver + docker-maintenance migrations land via STATBUS-191 (engineer-ready, NOT King-gated, may close first); zero public-SSH CI consumers remain
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

author: architect
created: 2026-07-15 08:34
---
S2 BYTE REVIEW (architect, 2026-07-15): trace script SHIP AS-IS; runbook AMEND (4 items, 2 mandatory). Rulings first:

A. PART-D MECHANISM — the engineer's `docker network disconnect/connect` is CONFIRMED, overriding my own comment-#7 "docker stop/start" wording. His justification is correct and load-bearing: disconnect keeps the runner PROCESS alive, so the trace captures the in-process session-recovery signature — exactly layer (b)'s subject (a live process whose GitHub session died is the true-positive class the probe must detect). stop/start would capture a fresh-start registration signature — the wrong class.
B. FORCED-COMMAND PREFIX — HARDENED, not bare: keep `no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding,no-user-rc`. The restrictions are free for a one-command probe key held as a repo secret (the most exposed key class). Consistency with the fleet's bare form is restored by LEVELING UP, not down: the fleet's slot keys get the same options in a separate small King-session item (foreman adds to the K-list / files LOW — separate because a broken forced-command locks CI out and needs its own careful verification; never smuggled into K2).

RUNBOOK AMENDMENTS:
A1 (MANDATORY): the prefix template says `command="/usr/bin/sshdo"` — wrong; the live path is `/usr/local/bin/sshdo` (foreman's root probe). The committed bytes must be correct — 167 discipline means the in-session grep is a CONFIRMATION, never a correction.
A2 (MANDATORY): reword step 3 — the grep-the-live-convention step confirms the SSHDO PATH ONLY; the hardening options DELIBERATELY diverge from the (older, bare) fleet convention per ruling B, with the fleet leveling-up tracked separately. Without this rewording, the King ratifying "against the live line" would strip the hardening.
A3 (minor): step 5's refused-test `|| echo OK` also prints OK on a transport failure (false pass) — assert the refusal TEXT instead (grep for 'not in allowlist', the exact string the 170 sshdo proof used).
A4 (minor): the hand-back section says "AC#9" — 069's canary re-add is AC#5.

APPROVED BEYOND SPEC, noted: the smoke-test-BEFORE-shred step (5) — proves key+sshdo+script end-to-end while recovery is still one keygen away; and the trace tool's read-only-default + refuses-while-Runner.Worker-alive + unknown-arg exit 2 are all right. After A1-A4 the foreman commits; K1 becomes the one-command ask.
---

author: foreman
created: 2026-07-15 08:43
---
NEW KING SESSION ITEM (architect S2 review, 2026-07-15) — recorded for the K-list: HARDEN THE EXISTING SLOT KEYS' FORCED-COMMANDS. The canary key's forced-command is ruled HARDENED (command="/usr/local/bin/sshdo" + no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding,no-user-rc — free for the most-exposed key class, a repo-secret probe key). Fleet consistency is restored by leveling UP: apply the same no-* options to the existing seven slot keys' bare command="/usr/local/bin/sshdo" lines. Kept a SEPARATE King session item (NOT folded into K2): a broken forced-command locks CI out of that slot, so it needs its own before/after verification — never smuggled into the canary provisioning. Foreman-verified live baseline (2026-07-15 root probe): all seven slot keys currently use the BARE prefix; /usr/local/bin/sshdo is the correct binary path.
---

author: foreman
created: 2026-07-20 11:56
---
K1 TRACE CAPTURED (2026-07-20; foreman-run with the King's explicit root@niue grant — the King delegated the K1 touchpoint in chat; committed script bytes piped over ssh, --with-disconnect arm included). Full output: tmp/runner-health-trace-K1.out (repo tree, 100 lines). KEY SIGNATURES: (A) container Running=true RestartCount=0, started 2026-07-19T03:17:58Z. (B) IDLE CADENCE: one token-refresh pair (RSAFileKeyManager 'Loading RSA key parameters' + GitHubActionsService 'AAD Correlation ID') every ~50 minutes, metronomic across 9+ hours (02:19, 03:10, 04:00, 04:50 … 11:31). 'Listening for Jobs' appears ONCE per session (02:19:56) — confirming the architect's do-not-pin ruling. (C) Runner.Listener running, no Runner.Worker (idle); _diag Runner_*.log files current. (D) DISCONNECT SIGNATURE — the notable finding: during the 60s network drop AND in the immediate post-reconnect window, docker logs emitted NOTHING (both capture sections empty). The runner reconnects silently at the docker-logs layer; the offline signature, if any, lives in _diag retry lines, not container stdout. Layer-b calibration must therefore key on staleness of the ~50-min token-refresh cadence (e.g. 'no refresh pair within ~60 min = stale') rather than any positive offline line. S5 (engineer calibration → final bytes → architect S6 review) dispatched.
---

author: architect
created: 2026-07-20 12:06
---
S6 FINAL-BYTES REVIEW (architect, 2026-07-20) — verdict: APPROVE WITH ONE AMENDMENT. Both judgment calls ruled below. After the amendment lands, a delta look at those lines only, then S7 commit.

JUDGMENT CALL 1 — FRESH_WINDOW: 65m CONFIRMED over the ~60m suggestion. A false RED on this canary is the expensive direction — it burns an investigation and teaches people to distrust the probe (wolf-crying), while the cost of 65m over 60m is five extra minutes of detection latency on a signal consumed at push time, already bounded by the notify legs. 12 cycles is also a small sample for cadence stability — the margin absorbs server-side TTL drift. The env override covers tuning without a re-provision.

JUDGMENT CALL 2 — b1 KEEP. It is not signal impurity: without b1, a crashed Listener stays GREEN for up to FRESH_WINDOW after its last refresh (b2 only reds when the window expires); b1 makes that immediate and disambiguates process-dead from refresh-wedged in the verdict line. Both signals fail closed and AND-compose — no masking direction exists.

THE AMENDMENT (must-fix, exact bytes): b1 currently runs ps INSIDE the third-party runner container (docker exec … ps). If a runner-image update drops procps, the pipeline fails and b1 reports 'Listener is not running' — a FALSE RED with a MISLEADING message, on a script in the sshdoers trust class that needs a King provisioning session to change. Fix: host-side listing via docker top (the host's ps over the container's PIDs) — zero in-container dependencies, which also perfects the self-contained hard requirement. EMPIRICALLY VERIFIED on a live daemon before prescribing (test-to-know): `docker top C -eo args` FAILS with 'Couldn't find PID field in ps output' (the daemon must map output lines to PIDs); `docker top C -eo pid,args` works. The bytes:

  procs="$(docker top "$C" -eo pid,args 2>&1)" || {
    echo "UNHEALTHY: cannot list container processes (docker top error: ${procs}) — Listener liveness UNVERIFIABLE. [layer b1]"
    exit 2
  }
  if ! printf '%s' "$procs" | grep -q "[R]unner.Listener"; then
    echo "UNHEALTHY: container '$C' is up but the Runner.Listener process is not running — the runner is not connected to GitHub. [layer b1]"
    exit 2
  fi

plus a header/comment line carrying the pid-column constraint ('docker top requires a pid column — keep -eo pid,args') so a future editor cannot simplify it into the failing form. Same exit 2 for unverifiable-vs-dead is fine — the contract's signal is nonzero + a message naming the layer, and the messages are distinct.

FOLD-IN (same pass, one line): b2's docker-error branch currently swallows the error detail (2>&1 captures it into $logs, then the exit-4 message omits it). Name it: `echo "UNHEALTHY: cannot read '$C' logs (docker error: ${logs}) — freshness UNVERIFIABLE. [layer b2]"` — on a box we can only touch via a King session, the remote verdict line should carry the diagnosis.

APPROVED AS BUILT, everything else: layer (a) unchanged (a restart-looping container reports Running=false → red, correct); the calibrated header narrative carrying the K1 trace evidence WITH the bytes (exactly the cold-agent property S6 exists to check — durable copy in comment #10); staleness-keying as the ruled fallback given Part D's zero-signature finding; the do-not-pin 'Listening for Jobs' observation; the documented refresh-ATTEMPT residual bounded by the notify legs (doc-026, unchanged); DRAFT banner removal; canary wiring untouched pending AC#5 post-K2.
---

author: architect
created: 2026-07-20 12:09
---
S6 DELTA LOOK (architect, 2026-07-20) — SHIP. Both amended hunks are byte-faithful to comment #11: b1 = host-side `docker top "$C" -eo pid,args` with capture-and-distinguish (docker-error vs no-match, distinct messages, both exit 2) and the pinned pid-column constraint comment; b2's exit-4 branch names the captured docker error. Independent bash -n clean. Self-containment is now total — external surface is docker inspect/top/logs + POSIX builtins, zero in-container dependencies. Foreman: commit (S7); K2 joins the King's queue with the runbook installing these exact bytes.
---

author: foreman
created: 2026-07-20 12:09
---
S7 COMMITTED (da7e46af4, pushed): runner-health.sh final bytes — layer (b) = b1 (Listener alive via host-side docker top, capture-and-distinguish, pid-column constraint pinned) AND b2 (token-refresh marker within FRESH_WINDOW=65m, env-overridable), both fail-closed, exit 0 only on container+Listener+fresh. Calibrated from the K1 trace (comment #10); architect S6 review (comment #11) + delta look (comment #12) both green; engineer applied the amendment verbatim. AC#3 checked. NEXT: K2 — the King's one-session provisioning (runbook ops/github-runner/runner-health-K2-runbook.md at these committed bytes: install script root-owned at /usr/local/sbin/statbus-runner-health with visual diff, ssh-keygen, the printed sshdoers + authorized_keys lines, gh secret set RUNNER_HEALTH_SSH_KEY, shred) — queued to the King. Then S9 canary re-add + the one-push proof (AC#5) closes the canary half.
---

author: architect
created: 2026-07-20 12:40
---
b2 FALSE-STALE BUG RULED (architect, 2026-07-20) — root cause CONFIRMED by local repro before ruling; exact bytes below. And owned plainly: my S6 + delta reviews missed this class — the smoke test caught what three reviews did not, which is the K2 runbook's smoke-before-shred step doing exactly its job (test-to-know).

MECHANISM, verified: under `set -o pipefail`, `printf '%s' "$logs" | grep -qF …` breaks on a LARGE buffer — grep -q exits 0 at the FIRST match and closes the pipe; printf is still writing → SIGPIPE → rc 141 → pipefail turns the whole pipeline non-zero → `if !` reads a MATCH as a MISS → false STALE (exit 3) with the observed 'printf: write error: Broken pipe'. Repro (run locally, 2026-07-20): pipe form → WRONG-STALE; herestring form → correct. The trigger condition — a big docker-logs buffer — is precisely 'a CI job ran recently', the runner's COMMON state: every prior green test had small idle buffers. b1's `printf "$procs" | grep -q` is the same latent shape, masked only by small process lists. FALSE-RED direction, and worse: a WRONG false red (names staleness while the session is fresh) — exactly the wolf-crying class the 65m ruling paid to avoid.

THE FIX (exact bytes — eliminate the PIPE, not the -q; herestrings have no writer to SIGPIPE):

b1 line:
  if ! grep -q "[R]unner.Listener" <<<"$procs"; then

b2 line:
  if ! grep -qF "$TOKEN_MARK" <<<"$logs"; then

plus ONE class-naming comment, placed at the `set -uo pipefail` line so the constraint travels with its cause:
  # NO pipes into grep -q in this script: under pipefail, grep -q's early exit
  # SIGPIPEs the writer on a large buffer (rc 141) → the pipeline goes non-zero
  # → a MATCH reads as a MISS (false STALE — caught by the K2 smoke test,
  # 2026-07-20, right after a CI job ran). Herestrings (<<<) have no pipe.

Rejected alternative, for the record: `… | grep -F … >/dev/null` (full read, no early exit) also works but KEEPS the pipe — the class survives for the next editor who 'optimizes' back to -q. The herestring deletes the class.

PROCESS: engineer applies verbatim → my delta look at the two lines + comment → foreman re-commits AND re-provisions root-owned under the standing grant (the installed sha256 changes — re-verify the visual diff against the new commit) → re-smoke: permitted probe must return HEALTHY exit 0 with the job-inflated log buffer, refused path re-checked → only then K2 step 6 (gh secret set + shred). Holding step 6 was the right call — the key never leaves the scratchpad until the probe tells the truth.
---

author: architect
created: 2026-07-20 12:46
---
HERESTRING FIX DELTA LOOK (architect, 2026-07-20) — SHIP. Byte-faithful to comment #14: b1 and b2 both read `if ! grep -q… <<<"$buf"`, the class-naming comment sits at the set -uo pipefail line carrying the mechanism + the K2 catch. Independently verified: bash -n clean, shellcheck clean, and a whole-file grep confirms ZERO pipes into grep -q remain. Foreman: re-commit → re-provision root-owned under the standing grant (fresh visual diff against the new commit's sha) → re-smoke — the permitted probe must return HEALTHY exit 0 against the SAME job-inflated buffer class that triggered the false-stale, refused path re-checked — → only then K2 step 6 (gh secret set + shred). The re-smoke against the inflated buffer is the load-bearing check: it is the exact condition all pre-fix green tests never exercised.
---

author: foreman
created: 2026-07-20 12:47
---
K2 COMPLETE (2026-07-20, foreman under the King's explicit grant; AC#4 checked). Full session record: (1) probe script installed root-owned at /usr/local/sbin/statbus-runner-health — first from da7e46af4, then RE-PROVISIONED from 0e3d524a5 after the smoke test caught the pipe-into-grep-q false-stale (comments #14/#15); installed sha256 fe6837a6… verified byte-identical to the reviewed commit both times. (2) Ephemeral-mint deviation, custody-equivalent: keypair minted on the foreman's machine (not on niue) so the PRIVATE half never crossed the wire; public half scp'd. (3) Hardened forced-command line on github-runner's authorized_keys (canary standard prefix); sshdoers line 'github-runner: /usr/local/sbin/statbus-runner-health' appended with backup /etc/sshdoers.bak-20260720-statbus069-k2. (4) SMOKE, the load-bearing run: refused path — 'id' denied 'not in allowlist'; permitted path — FIRST smoke returned false-stale exit 3 + broken-pipe on line 84 (the bug find, with a 91k-line job-inflated buffer); after the herestring fix + re-provision, the re-smoke against the SAME 91,141-line buffer returned: 'HEALTHY: container running, Runner.Listener alive, GitHub session fresh (token refresh within 65m).' exit 0 — the first real b2 proof under the runner's common post-job state. (5) Step 6: RUNNER_HEALTH_SSH_KEY repo secret set (2026-07-20T12:46:58Z, verified via gh secret list); local private key overwrite-deleted, zero key files remain. REMAINING on this ticket: AC#5 only — engineer re-adds the hosted runner-online canary job (self-hosted legs needs: it), foreman pushes, ONE PUSH proves the canary green-gating. Queued to the engineer behind the STATBUS-193 build.
---
<!-- COMMENTS:END -->
