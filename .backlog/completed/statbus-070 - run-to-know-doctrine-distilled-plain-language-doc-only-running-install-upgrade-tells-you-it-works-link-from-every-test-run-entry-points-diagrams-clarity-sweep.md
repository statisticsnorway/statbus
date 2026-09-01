---
id: STATBUS-070
title: >-
  run-to-know-doctrine: distilled plain-language doc "only running
  install/upgrade tells you it works" + link from every test run, entry points,
  diagrams + clarity sweep
status: Done
assignee: []
created_date: '2026-06-17 08:26'
updated_date: '2026-06-17 20:36'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DONE (foreman, committed 6a0a8398e, pushed): (1) DOCTRINE doc/install-upgrade-testing.md — plain words, zero ceremony: the rule (only running it tells you), the loop (commit→push→build→run→observe→iterate), why these tests are special (others run pre-push; install/upgrade cannot), the corollary (stalling = zero knowledge; uncertainty→run; the run is the only judge), why we keep tests+diagrams (ground truth + the map), and the live STATBUS-067 example. (2) LINKED from: run.sh (prints on EVERY run, after --print-selected guard), README top callout, AGENTS.md install/upgrade section, doc/upgrade-timeline.md, doc/upgrade-hardening.md, and all 3 diagrams via `legend top` blocks (install-recovery / upgrade-timeline / upgrade-lifecycle) — plantuml -checkonly green, SVGs regenerated. (3) CLARITY stab: README now LEADS with the one plain-language goal every scenario proves — 'if the machine dies at a dangerous moment, re-running ./sb install (and nothing else) must recover the system coherently, data intact; read each scenario as die HERE → operator re-run ends THERE, data intact' — so the goal is no longer buried under C3/R5/Fix-11 codes.

REMAINING (open): the per-scenario catalogue rewrite — lead EACH of the ~24 README entries (and ideally each scenario .sh header) with its plain goal first, mechanism/codes as grounding below. The top-level one-goal framing is in; the per-entry rewrite is a clarity polish. Standard set by the doctrine doc + the README framing; can delegate to mechanic/operator against that exemplar, or do on King's word.

DONE (foreman, 2026-06-17): the remaining per-scenario clarity pass is committed + pushed as 5efe6dfe7. The install-recovery README scenario catalogue now LEADS each entry with its plain goal ('die HERE -> the operator's ./sb install re-run must end THERE, data intact'), with the mechanism (inject site, C-class, the fix it guards) as grounding beside it, organized by phase. ALSO completed the catalogue: it was missing 6 of the 32 scenarios (checkout-kill-legacy, archivebackup-watchdog, mid-tx-kill, migration-deterministic-error, resume-died-rollback, rollback-restore-watchdog) — all 32 now listed + VERIFIED to match scenarios/ exactly (diff clean). Combined with the earlier doctrine doc + links (6a0a8398e), 070's three parts (write the doctrine / link it widely / clarity sweep) are all delivered. FOLLOW-UP FILED (separate, not 070's scope): the README's Debugging/Cleanup/CI-integration sections are stale — they describe the retired local-multipass tool (multipass appears ONLY in the README; the harness uses hcloud/Hetzner per lib/* + run.sh, and IS CI-integrated via install-recovery-harness.yaml). → new task.
<!-- SECTION:NOTES:END -->
