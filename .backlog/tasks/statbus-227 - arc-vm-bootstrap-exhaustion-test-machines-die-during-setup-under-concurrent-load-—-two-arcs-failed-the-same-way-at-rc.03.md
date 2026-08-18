---
id: STATBUS-227
title: >-
  arc-vm-bootstrap-exhaustion: test machines die during setup under concurrent
  load — two arcs failed the same way at rc.03
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-18 10:14'
updated_date: '2026-08-18 11:57'
labels:
  - install-recovery
  - ci
  - infra
dependencies: []
references:
  - ops/setup-ubuntu-lts-24.sh
  - test/install-recovery/lib/vm-bootstrap.sh
  - .github/workflows/upgrade-arc-harness.yaml
priority: medium
type: bug
ordinal: 227000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Our upgrade tests run on small rented machines, and the machines themselves are dying during setup before the test even starts. At rc.03, two of the 36 test jobs failed this way — not our code, but no longer dismissible as bad luck, because both failed identically.

WHAT THE EVIDENCE SHOWS: both victims (preswap-binary-swap-kill, then preswap-checkout-kill starting two seconds after the first died) reached late-stage setup — the heavy package installs (a 226MB editor among them) — and then the machine simply went quiet: SSH reads timed out, the harness failed at vm-bootstrap.sh:675 with "HARDENING FAILED ... (empty = SSH read failure)". Same Hetzner zone (hel1), same smallest tier (cx23), same phase, back-to-back provisioning waves. Both scenarios passed at earlier tags. Full triage: tmp/operator-arc-preswap-triage-2026-08-18.md and tmp/operator-arc-fail2-triage-2026-08-18.md.

THE DESIGN QUESTION (architect rules — the obvious fixes conflict with a principle): (a) leaner setup — but ops/setup-ubuntu-lts-24.sh is the REAL operator setup script, and the harness's value is testing exactly what operators run; a test-only slim profile re-opens the divergence the harness exists to close. (b) bigger tier (cx33) — costs more across 31 VMs per full suite. (c) staggered provisioning or lower concurrency — cheaper, slower wall-clock. (d) something else the evidence suggests, e.g. asking whether a disposable test box needs the interactive comfort tools at all — which is really question (a) posed about the OPERATOR script's own contents.

WHAT IS ACHIEVED: test failures mean product defects again, not rented-machine roulette — the suite's red becomes trustworthy, and nobody spends a morning triaging a machine that starved.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect ruling on the remedy (lean setup vs tier vs stagger vs other), with the operator-parity principle explicitly weighed
- [ ] #2 The chosen remedy implemented and the two failed scenarios pass on rerun
- [ ] #3 No recurrence of the signature across one full subsequent suite
- [ ] #4 Bootstrap-failure forensics captured BEFORE the VM is destroyed: post-failure reachability probe (fresh SSH/ping/provider power state), dmesg or journalctl -k (the OOM killer names its victim), free -m, df -h, and provider console output for the window — so a recurrence is a measurement, not an absence of news
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-18 10:18
---
RULED — doc-032. Option (d), and it is NOT a compromise between test reliability and operator parity: it DISSOLVES the tension. Delete the Homebrew comfort layer from ops/setup-ubuntu-lts-24.sh — Homebrew itself, build-essential, helix, bottom, zellij, and their verifications. Keep the apt toolkit (neovim, htop, ripgrep, git, net-tools, jnettop, acl, aptitude): an operator diagnosing a box needs an editor, a monitor and a grep, and those are small, apt-managed, and patched by the very mechanism this script installs.

PARITY IS PRESERVED, NOT TRADED. The harness keeps running the REAL operator script. No test-only slim profile, no divergence reopened. The script gets smaller, faster, safer AND the test machines stop dying — one change, both benefits, because they were the same problem seen from two ends.

WHY THE COMFORT LAYER IS WRONG ON THE SCRIPT'S OWN TERMS, independent of any test failure:
1. IT CONTRADICTS THE HARDENING THE SAME SCRIPT PERFORMS. Earlier stages configure unattended-upgrades, CrowdSec + firewall bouncer and ufw; Stage 6 then installs a PARALLEL package tree unattended-upgrades will never patch. A brew-installed openssl on a production box gets no security updates from the mechanism this script just set up. It also leaves build-essential — a full compiler toolchain — on a hardened host.
2. IT DUPLICATES APT: apt gives neovim and htop; brew adds helix (second editor) and bottom (second monitor).
3. THE SCRIPT ALREADY CALLS THESE OPTIONAL AND THEN CONTRADICTS ITSELF: the install is failure-tolerant (`brew install helix bottom zellij || { log "…not available — skipping" }`) but the four following `verify` calls are unconditional, so a genuinely skipped install still records failed verifications. The author's own judgement was that these are optional; only the verification block disagrees.

CHECKED AND CLEARED so nobody chases it: the zellij auto-attach in /etc/profile.d/zellij.sh IS guarded by `[ -n "$PS1" ]`, so non-interactive SSH — harness, deploy workflows, the upgrade system's remote calls — is unaffected. Not a hazard.

TWO CORRECTIONS TO THE TRIAGE, both load-bearing:
(i) "THE VM BECAME UNRESPONSIVE" IS A HYPOTHESIS, NOT A FINDING. What was observed is that ONE SSH READ RETURNED NOTHING. Nobody probed whether the box was still alive, and it was destroyed on teardown — so "machine died" and "machine too busy to answer inside our read timeout" fit every byte of evidence equally well. Different remedies; we cannot currently tell them apart.
(ii) THE CONTROL-LINE CLASSIFICATION IS WRONG. Whether a rented machine dies is outside our control; WHAT WE CHOOSE TO RUN ON IT during setup is entirely inside it. Responsibility follows the control line — this one is ours.

ON "IS DELETING IT A WORKAROUND, SINCE THE MECHANISM IS UNPROVEN?" — the no-flaky rule forbids DISMISSING a failure as bad luck, not removing an unnecessary step we cannot yet fully explain. We need not know which resource ran out to justify deleting a phase that puts a compiler and a second package manager on a hardened production host for a nicer editor. If the phase were load-bearing, deleting it would be routing around the problem. It is not, and the script is better without it even if no test machine had ever failed.

REJECTED — (b) BIGGER TIER: buys silence over a symptom, costs money on every VM of every suite, and REDUCES parity in the direction that matters — a statistical office may well run a small box, so the smallest tier is the honest thing to test on. Raising it HIDES exactly the class of failure an operator would hit.
REJECTED AS PRIMARY — (c) STAGGER/LOWER CONCURRENCY: symptomatic, and pays wall-clock on a release path already measured in hours. HELD IN RESERVE: if the signature recurs after the remedy, concurrency becomes the live hypothesis with evidence behind it.

SECOND HALF, A DELIVERABLE NOT A NICETY — STOP GUESSING. Before the next suite the bootstrap-failure path must capture, BEFORE the VM is destroyed: a reachability probe after the read failure (ping, a FRESH ssh connection, the provider's power-state view — a box that answers a new connection was never dead); `dmesg`/`journalctl -k` (the OOM killer NAMES its victim, settling the memory hypothesis outright) plus `free -m` and `df -h`; and the provider's console output for the window, which survives a wedged kernel. The teardown trap runs the collection and attaches it to the job. Then AC#3's "no recurrence" is a measurement, not an absence of news. Add it as an explicit acceptance criterion so it cannot quietly drop out.

SEQUENCING: agreed — solo reruns of the two failed jobs after drain regardless (a solo rerun cannot reproduce concurrent-wave exhaustion, so rc.03 can still complete green); this remedy targets the NEXT suite.
---

author: foreman
created: 2026-08-18 10:19
---
SEQUENCING (foreman): assigned to the mechanic, queued as his unit AFTER the orchestrator lands and the 223+220 arc-file pass (223 and 220 share upgrade-arc-harness.yaml, so they go as one unit; 227 is its own unit in ops/setup-ubuntu-lts-24.sh + test/install-recovery/lib/vm-bootstrap.sh). The architect's forensics deliverable is now AC#4 so it cannot drop out of the unit. FLAG TO THE KING, standing in my console: the ruling DELETES the Homebrew comfort layer (brew itself, build-essential, helix, bottom, zellij) from the REAL operator setup script — the apt toolkit (neovim, htop, ripgrep…) stays. If anyone relies on those tools on production boxes, object before the unit ships; the security case for deletion (unpatched parallel package tree + compiler toolchain on a hardened host) is on doc-032.
---

author: foreman
created: 2026-08-18 11:33
---
KING RATIFIED the comfort-layer deletion, 2026-08-18, foreman's console: "Approved, it slims the install." RE-SEQUENCED: the mechanic builds this NOW (ops/setup-ubuntu-lts-24.sh + test/install-recovery/lib/vm-bootstrap.sh are disjoint from his frozen orchestrator files), so the next RC cut carries the starvation remedy; 223+220 follow after the orchestrator lands as before.
---

author: mechanic
created: 2026-08-18 11:57
---
Built per doc-032 exactly, frozen for review (no commits) — second frozen unit beside 214, shares no files with it. Part 1/2: the comfort-layer deletion.

ops/setup-ubuntu-lts-24.sh, Stage 6 (renamed "User Setup (devops)", was "& Developer Tools"): DELETED
- `apt-get install -y build-essential curl file git procps` (Homebrew's own dependency install)
- the whole Homebrew bootstrap block: mkdir/chown /home/linuxbrew, the NONINTERACTIVE brew install.sh curl-pipe, ACL/ownership setup, /etc/profile.d/linuxbrew.sh (PATH + shellenv + bash-completion), the `git config --system safe.directory` for linuxbrew
- `brew install helix bottom zellij` + its failure-tolerant fallback log line
- /etc/profile.d/zellij.sh (auto-attach) + its chmod
- verify() calls: "Homebrew installed", "helix installed", "bottom installed", "zellij installed", "zellij auto-attach configured" (5 removed)
- the 3 stage-description echo lines ("Install Homebrew", "Install: helix, bottom, zellij", "Configure zellij auto-attach") and the matching --help stage-list + final-summary echo lines

KEPT, unchanged: devops user creation, passwordless sudo, SSH key population (GITHUB_USERS/GITHUB_DEPLOY_KEYS), ed25519 keypair generation, docker group membership, and every verify() for those. Stage 5's apt toolkit (neovim, htop, ripgrep, git, net-tools, jnettop, acl, aptitude) is untouched — not in Stage 6's scope, never was. Replaced the deleted block with a comment naming STATBUS-227/doc-032 and the exact reasoning, pointing at .backlog/docs/doc-032 for the full ruling.

STAGE STRUCTURE / FAILED_VERIFICATIONS check: coherent — Stage 6 still runs verify() calls for everything it still does, no orphaned verify targets, stage numbering (0-7) untouched, main()'s end-of-run FAILED_VERIFICATIONS aggregation logic itself untouched (STATBUS-207's mechanism, lines ~1296-1310, not in the diff at all).

Also caught two stale-prose spots while in the area (doc-accuracy, not functional): a Homebrew-attributing comment in vm-bootstrap.sh's `_apply_hardening` caller ("bootstrap activity (Homebrew installs, service starts) can leave sshd's accept queue saturated") updated to not name a mechanism that no longer exists; --help's Stage 6 one-liner and the final "Summary of configuration" echo both updated to match.

207 GOAL-BASED STAGES cross-check: grepped test/install-recovery/lib/*.sh and scenarios/*.sh for helix/zellij/bottom/linuxbrew/Homebrew — zero hits outside comments already updated. Nothing in the harness's own goal-based verification depends on any deleted tool; the harness only cares that Stage 6 (SSH/user setup) succeeds, which it still does, unchanged.

Validated: `bash -n ops/setup-ubuntu-lts-24.sh` clean. `shellcheck` diffed against the pre-edit baseline (git show HEAD:...) — byte-identical finding set (same pre-existing SC2034/SC2164/SC1091 warnings, zero new, zero removed, only line numbers shifted). Part 2/2 (AC#4 forensics in vm-bootstrap.sh) follows in the next comment.
---

author: mechanic
created: 2026-08-18 11:57
---
Part 2/2 — AC#4 forensics in test/install-recovery/lib/vm-bootstrap.sh.

New function `_dump_bootstrap_failure_diagnostics IP VM_NAME`, defined immediately before `_apply_hardening` (its only call site) and called from BOTH of `_apply_hardening`'s failure paths — the "HARDENING TIMEOUT" branch and the "HARDENING FAILED with exit code" branch — right before each `return 1`, while VM_IP is still valid and before the caller's EXIT trap runs cleanup_vm. Same house pattern as the existing `_dump_unit_diagnostics` (called by vm_restart_unit/vm_start_unit on failure, same "capture before teardown" placement), not invented fresh.

Captures, in order, every step individually `timeout`-bounded and `|| echo ...`-tolerant (the whole file runs under `set -euo pipefail`, so every command in the new function has an explicit non-abort fallback, matching `_dump_unit_diagnostics`'s existing style):
1. `ping -c 3 -W 3` — ICMP reachability.
2. A FRESH ssh connection (own `ConnectTimeout=10`, does not reuse whatever connection just failed) running `echo ... uptime -p` — the doc-032 point verbatim: a box that answers a NEW connection was never dead. Logs which branch it took.
3. `hcloud server describe $vm_name -o format='{{.Status}}'` — provider's own power-state view.
4. One more fresh-SSH call bundling `dmesg | tail -100`, `journalctl -k --no-pager | tail -100`, `free -m`, `df -h` — gated on reachability (if the box is truly dead this whole block just reports "unreachable", which is itself the answer AC#4 wants: a measurement, not a guess).
5. `hcloud server request-console $vm_name` — see the disclosure below.

DISCLOSURE, not a silent shortfall: doc-032 asks for "provider console output for the window, which survives a wedged kernel." Checked `hcloud server --help` / `hcloud server request-console --help` against the working `hcloud` CLI (v1.65.0) — Hetzner Cloud's console is an interactive VNC WebSocket session (URL + short-lived token), NOT a text serial-console-log endpoint. Unlike AWS's get-console-output or DigitalOcean's console log, there is no `hcloud` command that returns a text dump of boot/console output. I could not find one, and the CLI's own subcommand list (create/describe/rebuild/delete/poweroff.../request-console, no "console-log"/"serial-log") confirms it isn't hidden somewhere. What I built: request a console session and log its (short-lived) URL for a human to use MANUALLY for post-mortem — only useful if `KEEP_VM_ON_FAILURE=1` kept the box alive past the run. A real-time VNC screen-grab (would show a kernel panic on a truly wedged box) is technically possible via a websocket client but is a materially bigger build (extra tooling, frame decode) than doc-032's "about five lines" framing anticipated for the rest of this AC — flagging as a gap between the ruling's ask and this provider's actual API, not routing around it. Your call whether that's worth a follow-up ticket.

Also fixed one stale comment while in the area: `_apply_hardening`'s "Wait for SSH to be responsive" comment used to attribute accept-queue saturation to "Homebrew installs" — updated to not name a mechanism that no longer exists (ordinary apt/service-start activity can still cause the same symptom, so the `_wait_for_ssh` call itself is unaffected and still correct).

Validated: `bash -n test/install-recovery/lib/vm-bootstrap.sh` clean. `shellcheck` diffed against the pre-edit baseline — one new info-level SC2016 surfaced on the intentionally-single-quoted remote command string (the `$(...)` must expand on the VM, not locally); silenced with a `# shellcheck disable=SC2016` comment naming exactly why (matches how the file already handles this for its other remote command strings). Re-diffed after: byte-identical to baseline, zero new findings.

Both files' diffs frozen together (no commits), share no files with the STATBUS-214 unit. Ready for review; landing still gated on whatever verification you want beyond the two failed scenarios' solo rerun (AC#2/#3 need a live suite, which I can't produce from here).
---
<!-- COMMENTS:END -->
