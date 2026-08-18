---
id: STATBUS-227
title: >-
  arc-vm-bootstrap-exhaustion: test machines die during setup under concurrent
  load — two arcs failed the same way at rc.03
status: To Do
assignee:
  - mechanic
created_date: '2026-08-18 10:14'
updated_date: '2026-08-18 10:19'
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
<!-- COMMENTS:END -->
