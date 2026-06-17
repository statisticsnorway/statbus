---
id: STATBUS-070
title: >-
  run-to-know-doctrine: distilled plain-language doc "only running
  install/upgrade tells you it works" + link from every test run, entry points,
  diagrams + clarity sweep
status: To Do
assignee: []
created_date: '2026-06-17 08:26'
labels:
  - docs
  - install-recovery
  - upgrade
  - clarity
  - testing-philosophy
dependencies: []
priority: high
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KING DIRECTIVE (2026-06-17), three parts:

1. WRITE THE DOCTRINE (distilled, plain words, ZERO ceremony): the knowledge of whether a change to install/upgrade/recovery works can ONLY be obtained by running the experiment — and "running the experiment" here means EXACTLY: commit → push to master → CI builds the per-commit image → run that image on a real VM (install-recovery harness) → observe the result → iterate. There is no shortcut. These tests are SPECIAL: every other suite (pg_regress/SQL, Go tests, integration) can mostly be run BEFORE pushing; install/upgrade CANNOT — they require commit→push→observe by design (that is the entire reason the per-commit-image CI pipeline exists). Stalling before running is not an option — it produces zero knowledge. The problem is too hard to theorize about; that is WHY we have the tests (ground truth) and the diagrams (think clearly through every case, see the coverage, confirm each one passes). HOME: doc/install-upgrade-testing.md.

2. LINK IT widely: (a) from EVERY test run — run.sh prints a one-line pointer at start; (b) at the top of test/install-recovery/README.md; (c) strategically where anyone enters this territory — AGENTS.md install/upgrade section, doc/upgrade-timeline.md, doc/upgrade-hardening.md; (d) in the diagrams — doc/diagrams/install-recovery.plantuml, upgrade-timeline.plantuml, upgrade-lifecycle.plantuml. NOT a memory — a checked-in, linked artifact.

3. EXTREME CLARITY is the North Star of every test + diagram: state the goal and exactly what each thing does, in plain words, no ceremony/bureaucracy. Without clarity we get lost in "maybe this, maybe that." DOUBLE-CHECK clarity across the harness. Observed gap: README scenario catalogue leads with internal codes (C3/C4/R1/R5, "Fix 6/7/8", inject-class names) — the plain-language GOAL of each scenario ("prove that if the machine dies during X, the operator's plain re-run recovers cleanly, data intact") is buried under the mechanism. Lead with the plain goal, keep the mechanism as grounding below.

CONTEXT that motivated this (live demonstration): STATBUS-067 canary — confident end-to-end analysis predicted terminal=rolled_back; the actual run (27674217081) returned completed with a consistent-looking DB. Nobody predicted it. Only running it revealed the bug may not be real. The doctrine is this lesson, generalized.

OWNER: foreman writes the doctrine + key links + sets the clarity standard (exemplar); broader scenario-catalogue clarity rewrite may delegate to the team against that standard.
<!-- SECTION:DESCRIPTION:END -->
