---
id: STATBUS-227
title: >-
  arc-vm-bootstrap-exhaustion: test machines die during setup under concurrent
  load — two arcs failed the same way at rc.03
status: To Do
assignee:
  - architect
created_date: '2026-08-18 10:14'
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
<!-- AC:END -->
