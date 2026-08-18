---
id: doc-032
title: 'arc-vm-bootstrap-exhaustion: design ruling for STATBUS-227'
type: specification
created_date: '2026-08-18 10:17'
tags:
  - install-recovery
  - ci
  - infra
  - architecture
---
# arc-vm-bootstrap-exhaustion — design ruling (STATBUS-227)

Architect ruling, 2026-08-18. Premises verified against the working tree at writing time.

## WHAT WE ARE PROTECTING

Setting up a StatBus machine should be the most reliable thing we do, because an operator in a statistical office gets one shot at it and their only remedy is to run it again. Today that setup ends by installing a second package manager, a compiler toolchain and three developer comfort tools — the least reliable part of the whole procedure, present for no operational reason, and now the part that is killing test machines.

## WHAT THE EVIDENCE SHOWS — AND WHAT IT DOES NOT

Two of 36 jobs at rc.03 failed identically. Both reached the same late phase and then the SSH session stopped responding: `HARDENING FAILED with exit code: '1' (empty = SSH read failure)` at vm-bootstrap.sh:675. Same zone, same smallest tier, back-to-back waves, both scenarios green at earlier tags. The last thing either machine reported was Homebrew work — `Installing zellij dependency: openssl@3`.

**The triage's central claim is a hypothesis, not a finding.** It states "the VM became unresponsive" and classifies the failure as outside our control. What was actually observed is that *one SSH read returned nothing*. Nobody probed whether the machine was still alive afterwards, and it was destroyed on teardown, so "the machine died" and "the machine was merely too busy to answer inside our read timeout" are equally consistent with every byte of evidence we hold. Those two have different remedies, and we cannot currently tell them apart. That gap is the second half of this ruling.

**The control-line classification is wrong, and it matters.** Whether a rented machine dies is outside our control. What we choose to run on it during setup is entirely inside it. Responsibility follows the control line: this is ours.

**What the setup script actually does.** `ops/setup-ubuntu-lts-24.sh` is a hardening script for the first two thirds of its length — etckeeper, unattended-upgrades, CrowdSec with a firewall bouncer, ufw, Docker — and installs a sensible operator toolkit from apt (neovim, htop, ripgrep, git, net-tools, jnettop, acl, aptitude). Then Stage 6 installs `build-essential`, bootstraps Homebrew from GitHub, and pours **helix** (a second editor), **bottom** (a second system monitor) and **zellij**.

Three observations follow from reading it:

- **The comfort layer contradicts the hardening layer.** The script carefully automates security patching through `unattended-upgrades`, then installs a parallel package tree that `unattended-upgrades` will never touch. A brew-installed openssl on a production box receives no security updates from the mechanism the same script just configured. It also leaves a full compiler toolchain on a hardened host.
- **The duplication is on the face of it.** apt already installed an editor and a system monitor; brew installs a second of each.
- **The script already treats these tools as optional, then contradicts itself.** The install is failure-tolerant — `brew install helix bottom zellij || { log "…not available for this architecture — skipping" }` — but the four `verify` calls that follow are unconditional, so a genuinely skipped install still records failed verifications. The author's own judgement was that these are optional; only the verification block disagrees.

One thing I expected to find and did not: the zellij auto-attach in `/etc/profile.d/zellij.sh` is correctly guarded by `[ -n "$PS1" ]`, so non-interactive SSH — the harness, the deploy workflows, the upgrade system's own remote calls — is unaffected. It is not a hazard and is not part of this remedy.

## THE RULING

**Option (d), and it is not a compromise between test speed and operator parity — it removes the conflict.** Delete the Homebrew comfort layer from the operator script: Homebrew itself, `build-essential`, helix, bottom, zellij, and their verifications. Keep the apt toolkit; an operator diagnosing a box needs an editor, a process monitor and a grep, and those are small, apt-managed, and patched by the mechanism the script already installs.

**Parity is preserved, not traded.** The harness keeps running the real operator script, unchanged in kind. There is no test-only profile and no divergence to reopen. The script gets smaller, faster, more reliable and more secure, and the test machines stop dying for the same reason — one change, both benefits, because they were the same problem seen from two ends.

**This is a fix, not a workaround, even though the mechanism is unproven.** The objection deserves a direct answer: the no-flaky-tests rule forbids dismissing a failure as bad luck, not removing an unnecessary step because we cannot yet explain exactly how it broke. We do not need to know which resource ran out in order to justify deleting a phase that installs a compiler and a second package manager onto a hardened production host for the sake of a nicer editor. If the phase were load-bearing, "delete it" would be routing around the problem; it is not load-bearing, and the operator script is better without it on grounds that stand even if the test machines had never failed.

**Rejected — (b), a bigger tier.** It buys silence over a symptom, costs money on every VM of every suite, and *reduces* parity in the direction that matters: a statistical office may well run a small box, so the smallest tier is the honest thing to test on. Raising it would hide exactly the class of failure an operator would hit.

**Rejected as the primary remedy — (c), stagger or lower concurrency.** It also treats a symptom, and pays in wall-clock on the release path, which is already hours. Hold it in reserve: if the signature recurs after the remedy, concurrency becomes the live hypothesis and this option returns with evidence behind it.

## THE SECOND HALF: STOP GUESSING

We are ruling on a mechanism we cannot see, and that must not happen twice. Every time we wish we could see something, we add the tool. Before the next suite, the harness's bootstrap-failure path must capture enough to distinguish a dead machine from a slow one, *before* the VM is destroyed:

- probe reachability after the read failure — ping, a fresh SSH connection, and the provider's own view of the server's power state; a machine that answers a new connection was never dead;
- capture `dmesg` / `journalctl -k` (the OOM killer names its victim, which settles the memory hypothesis outright) plus `free -m` and `df -h`;
- pull the provider's console output for the window, which survives even a genuinely wedged kernel.

The teardown trap must run this collection before deletion and attach it to the job. Then the next unexplained VM death arrives with its own diagnosis instead of a hypothesis, and AC#3's "no recurrence" is a measurement rather than an absence of news.

## WHAT IS ACHIEVED

An operator's one-shot setup stops depending on GitHub, on Homebrew's servers and on a small machine's ability to build packages, so the step most likely to strand a statistical office simply is not there any more. The hardened box stops carrying a compiler and an unpatched second package tree. And the suite's red goes back to meaning a product defect, because the part of setup that was failing is gone and the part that might fail next will explain itself.
