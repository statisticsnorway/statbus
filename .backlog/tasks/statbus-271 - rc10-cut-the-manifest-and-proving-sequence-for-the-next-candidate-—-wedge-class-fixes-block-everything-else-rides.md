---
id: STATBUS-271
title: >-
  rc10-cut: the manifest and proving sequence for the next candidate —
  wedge-class fixes block, everything else rides
status: To Do
assignee: []
created_date: '2026-08-27 13:08'
updated_date: '2026-08-28 15:23'
labels:
  - release
dependencies: []
priority: high
type: task
ordinal: 264000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King's directive (2026-08-27): cut the next candidate as soon as ready; a stable release follows (Ukraine + the fleet wait on it). Architect's ruled manifest, criterion = "does it close the wedge class":

BLOCKING: STATBUS-264 + 265, landed TOGETHER or 265 FIRST — 264 alone would crash-loop a worker on a box legitimately holding the deliberate abort-hold read-only state (STATBUS-209 ARM A); 265's exemption dissolves that. Also blocking by sequencing: the 259 ENDGAME lands BEFORE THE CUT (not merely before the chain run — the cut triggers the chain immediately, and without the endgame rc.10 proves the obsolete transport and wastes a cut).

RIDES: 263 (task_cleanup FK — real bug, not the class; named as riding so it stops drifting as it has since May). 267 (stuck-task detector — detects wedges, doesn't prevent them; FIRST in the queue behind stable, the fleet is about to double). Nothing else on the board is release-blocking.

PROVING SEQUENCE TO STABLE: rune verified un-wedged (remedy RAN 2026-08-27 ~12:56Z — four tasks re-ran, parent completed, merge started; final drain confirmation pending) → rc.10 cut → chain run proves the NEW transport zero-hands on dev (closes 246/247/249/252 legs + 261's pending-arm) → human canary on no AGAINST doc-035's observation card, deviations become tickets before promotion (247 AC#7) → promote to stable — and the promotion gate ENFORCES this: it refuses until Norway carries a completed upgrade at the candidate's commit (247 AC#11), so the human step cannot be skipped under pressure → fleet follows NON-UNIFORMLY: demo auto-applies if 248's trigger is built; country boxes are OFFERED and a human opts in → Ukraine installs the stable (STATBUS-268).

RECORDED UNPROVEN, deliberately: 264's retry loop — once 265 lands the reset is exempt and never refused, so NO normal upgrade exercises the retry; its proof waits on STATBUS-270's spec suite or deliberate fault injection. Written down so rc.10's green is never read as covering it.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-27 19:39
---
v2026.08.0-rc.11 CUT (2026-08-27 evening, tag at 5399acd8b) — this candidate supersedes rc.10 as the one riding the proving sequence, carrying everything the manifest demanded plus the evening's landings: 263 (task_cleanup foundation — the named rider, no longer drifting), 264/265/266 (the wedge class, blocking items — landed pre-rc.10), 269 amendment, 280 (Stage 8 opt-in), 288 (staleness gate consults the executing workflow — proven live in this very cut's preflight: both migration-coverage refusals covered-by-construction with CI runs cited), and the go-test determinism fix. Preflight passed end to end with zero local test runs demanded. Chain running under watch. The proving sequence continues unchanged from here: chain green on dev → human canary on Norway against the observation card → promotion gate (which refuses until Norway carries a completed upgrade at the candidate's commit) → stable → fleet follows → Ukraine (already live on rc.10, channel=stable) is OFFERED the stable and a human opts in. RECORDED UNPROVEN carries forward: 264's retry loop still awaits STATBUS-279's fault-injection arc.
---

author: foreman
created: 2026-08-27 23:30
---
RC.11 CHAIN VERDICT (orchestrator 33109334330, completed 2026-08-27 ~23:05Z): FOUR OF FIVE LEGS GREEN — both install/upgrade smokes (proving 280's Stage-8 fix on real VMs), leg 3 dev takes the candidate automatically (the canary topology zero-hands), leg 4 install-recovery dispatched — but LEG 5 (upgrade arc harness, run 33115731212) RED: 8 scenario failures of 35. Mechanic's triage: TWO STANDING (restore-broke-reattempt = 227's bootstrap class, red pre-rc.11; rollback-pair-terminal = 228 family, red pre-rc.11; nothing red-before is green-now) and SIX NEW AT RC.11 — cross-version-rename-handoff, postswap-container-restart-kill, postswap-mid-migration-kill, postswap-mid-tx-kill, transient-db-backoff, un-park-to-completion — sharing ONE signature: the upgrade row never reaches its terminal state ('expected completed/rolled_back, actual available'; '?' where a row value should be; 'no terminal state within 1800s'). One regression, six costumes — suspect list is rc.11's upgrade/worker-path delta (263's worker startup calls + two migrations the leading hypothesis: a version-B worker starting against a schema-A database calling functions that do not exist yet). Engineer diagnosing with the King's overnight mandate active: root-cause → fix → land → foreman cuts rc.12 → chain re-proves. rc.11 MAY NOT BE PROMOTED (its own guard said so: nothing may be promoted).
---

author: foreman
created: 2026-08-28 00:52
---
v2026.08.0-rc.12 CUT (2026-08-28 ~00:45Z, tag at 5b44315c0, foreman under the King's overnight mandate after rc.11's leg-5 red). What it carries beyond rc.11: 267 (stuck-task detector), 282 complete (postmaster lock authority + guards, incl. the db-down pre-gate that briefly blocked CI), 285's publisher half (exercised-sha markers), 286's instrument, 288 (in rc.11 already), 290 formatting, 291 (channel filter + announce), AND THE ONE THAT DECIDES THE CHAIN: 293 — the CompareVersions incomparability enforcement + 12-site harness probe fix that ends the arc fleet's random-hex lottery. rc.11's six new arc reds were EXONERATED as that latent lottery (271 comment #2 and STATBUS-293); the two standing reds (restore-broke-reattempt=227, rollback-pair-terminal=228) are expected to remain — they predate every candidate and are the In Progress recovery backlog, NOT candidate regressions. Preflight passed with two stamp-only refreshes (types + doc-db for 267's migration; zero content diffs). The :708 sibling-guard unification landed as the first post-tag commit (432e51872). Chain watcher arming; verdict expected before morning.
---

author: foreman
created: 2026-08-28 02:39
---
rc.13 CUT (v2026.08.0-rc.13, tag at d663b2010, 2026-08-28 ~02:45Z) — third candidate of the night, under the King's overnight mandate. Carries exactly two changes over rc.12: 293's CompareVersions orderability fix (kills the leg-5 arc lottery) and 227's SIGPIPE sweep (kills the roving leg-4 hardening-verify red — 26 sites, f4b7a9507). Preflight green on the FIRST attempt, rides working as designed (go-test/app-build-lint rode from f4b7a950 over the board-only tip; fast-tests exercised the tip itself — and the 285 marker is visibly live in run names: 'Fast Tests @ exercised-sha=f4b7a95077e3…'). Orchestrator run 33136561614 in flight, watcher armed on the RUN ID. This is the first chain where both fixes are in the harness: legs 1-3 have passed twice tonight already; leg 4's only red cause is now fixed; leg 5 finally gets to run lottery-free. Expected honest residue if all else greens: the 228-family rollback-pair-terminal arcs — pre-existing backlog, not candidate regressions.
---

author: foreman
created: 2026-08-28 02:39
---
CORRECTION to #4: rc.13's delta over rc.12 is NOT '293 + 227' — 293 was already IN rc.12 (comment #3 says so; rc.12's leg 5 was SKIPPED because leg 4 failed, so 293 simply never got exercised). rc.13's actual delta: 227's SIGPIPE sweep (f4b7a9507) + the :708 sibling-guard unification (432e51872) + board commits. The substantive claim stands: rc.13's chain is the first where leg 4 runs with the SIGPIPE fix AND leg 5 runs at all with 293 in the fleet.
---

author: foreman
created: 2026-08-28 03:58
---
rc.13 CHAIN VERDICT (orchestrator 33136561614, completed 2026-08-28 ~04:20Z): LEGS 1-4 ALL GREEN — and leg 4 green is the night's proof: install-recovery passed for the FIRST TIME IN THREE CHAINS, confirming 227's SIGPIPE root cause and fix (the roving hardening-verify red is dead). Leg 5 red — but NOT an arc failure and NOT 293's lottery: the fleet NEVER LAUNCHED. Fixture construction died at exit 128 on a brand-new class bug: _ut_fixture_base's never-before-exercised nothing-to-commit arm leaks git commit's status chatter into its own stdout-returned SHA (STATBUS-295, filed with full mechanism; fired first at rc.13 precisely BECAUSE the tag sat at master's tip with workflows identical — the healthiest tag state we've cut all night is the one state the fixture code had never seen). Engineer on the fix. RELAUNCH IS CHEAP: the harness fixture job checks out the run's github.sha (master tip), not the tag — fix lands on master, then rerun the orchestrator's failed leg 5; rc.13 itself remains the candidate, no rc.14 required. 293 remains unexercised (the fleet must actually run to prove it); the 228-family standing reds remain the expected honest residue once the fleet flies.
---

author: foreman
created: 2026-08-28 04:20
---
rc.14 CUT (v2026.08.0-rc.14, tag at 50b13d70d, 2026-08-28 ~04:20Z) — fourth candidate of the night. Delta over rc.13: exactly the 295 fixture fix (84c99c7ed) + board commits. The cut waited on pg_regress at HEAD (run 33140883077) for the stale-template branch — the CI-oracle escape, satisfied by CI, zero local runs — then tagged. Orchestrator 33141502893 in flight, watcher armed on the run id. THE PROOF STRUCTURE OF THIS CHAIN: the tag again sits at master's tip, so leg 5's fixture construction walks the exact nothing-to-commit arm that killed rc.13 — the 295 fix's first live proof is the very candidate that carries it. If fixture construction survives, the fleet flies for the first time with 293 aboard, and the expected honest residue is the 228-family rollback-pair-terminal arcs only.
---

author: foreman
created: 2026-08-28 07:59
---
rc.14 FLEET, NEAR-FINAL (run 33145356673, 30 green / 3 flying / 1 red at this pin): the previously-standing rollback-pair-terminal family PASSED — the 'expected honest residue' turned out better than promised; this is already the cleanest arc run on record. THE ONE RED, triaged by the mechanic (evidence-first): cross-version-rename-handoff, IDENTICAL fingerprint to its rc.11 red ('no terminal state within 1800s' at arc.sh:66, 30:03 of total silence after 'Scheduled upgrade to v2026.08.0-rc.14', then 'service db is not running' in the diagnostics step). NOT 293's lottery — zero refusal/incomparable text in the log, scheduling succeeded cleanly, so the rc.11 exoneration was INCOMPLETE for this one scenario. THE LEAD, checked not assumed: the shape fits STATBUS-294's listener SIGSEGV exactly (schedule → executeUpgrade's teardown nils the shared conn → abandoned-listener race fires → the whole service dies → nothing left to progress the row = the 30-min silence), and 294's fix (efd07d036, landed this morning) is NOT in rc.14 — verified via git merge-base --is-ancestor: the tag predates the fix by 3 hours. EVIDENCE GAP stated honestly: the daemon journal for the stuck window was never captured — in EITHER run — because the harness's own diagnostics step aborts fail-fast on its first command when the db is down, destroying exactly the evidence it exists to collect; filed as STATBUS-296. DISPOSITION: rc.14 may not be promoted (one leg-5 red). The suspected cause is already fixed on master; the clean test is the next candidate, which carries 294 — its fleet either greens this scenario (confirming 294 as the cause) or reds it again with 296's fixed diagnostics capturing the journal that settles it either way.
---

author: foreman
created: 2026-08-28 08:12
---
rc.14 CHAIN FINAL VERDICT (orchestrator 33141502893 completed; arc fleet 33145356673: 34 GREEN / 2 red): the cleanest chain on record — legs 1-4 green, 295's fixture fix proven live on its exact arm, the rollback-pair-terminal family PASSED — and both reds are ONE bug, now CONFIRMED from the journal: transient-db-backoff's daemon log captured the panic live this run — 'panic: runtime error: invalid memory address or nil pointer dereference [signal SIGSEGV ... addr=0x90 pc=0x8ae1bc]' — byte-identical to rc.11's stack, i.e. STATBUS-294's abandoned-listener crash, whose fix (efd07d036) landed on master three hours AFTER rc.14's tag. cross-version-rename-handoff shares the signature (mechanic's triage; its journal was destroyed by the 296 gap, but the sibling scenario's live capture settles the family). NOTE the confirmation upgrades the mechanic's 'plausible, evidence-gapped' triage to CONFIRMED — the last fleet job delivered the journal his triage said was missing. DISPOSITION: rc.14 may not be promoted; rc.15 cuts next carrying 294 (the fix for both reds) + 296's diagnostics hardening (in flight, 12 arc scripts, mechanic building now) — the cut waits only for that freeze so the tree is clean. Expected: the first fully green chain.
---

author: foreman
created: 2026-08-28 08:59
---
rc.15 CUT (v2026.08.0-rc.15, tag at 2b3862bcc, 2026-08-28 ~09:00Z) — fifth candidate. Delta over rc.14, all landed this morning: 294 (the listener-ownership fix — the CONFIRMED cause of both rc.14 arc reds), 296 (25 arc diagnostics functions now survive the failures they document), 290's gofmt gate (passed its first live CI run in this very cut's go-test evidence), 292's content-hash refusal (plus the HEAD repair for my dev.sh sweep-in). Preflight green: images + fast-tests + pg_regress at the tip, go-test/app-build-lint riding from dec0b4baf over the board-only commit. Orchestrator 33157526472 queued, watcher armed on the run id. THE CLAIM THIS CHAIN TESTS: every red from four candidates is root-caused and its fix is aboard — 293's lottery, 227's SIGPIPE, 295's fixture pollution, 294's listener crash. Expected: the first FULLY GREEN chain, 36/36 arcs — and if anything new reds, 296's journals mean the triage reads a stack trace instead of arguing from silence. On green: rc.15 is the candidate for Norway's human canary against doc-035's observation card, then the promotion gate.
---

author: foreman
created: 2026-08-28 13:10
---
rc.15 CHAIN FINAL VERDICT (orchestrator 33157526472; fleet 33163032285: 33 GREEN / 3 red): legs 1-4 green again (leg 4's third consecutive green since the SIGPIPE fix; dev took its fifth candidate). The fleet's three reds: (1) cross-version-rename-handoff — FULLY DIAGNOSED during this very run (STATBUS-297: 254's guard firing on a both-keys collision only the harness constructs; remedy landed 27be9a72b, promotion NOT gated by it, zero real boxes carry the collision); (2) transient-db-backoff — RED DESPITE 294's fix being aboard, which reopens its attribution: either the fix failed (the journal will show the same SIGSEGV) or a second failure mode was hiding behind the crash — mechanic triaging from the journal now; (3) un-park-to-completion — a GREEN→RED flip from rc.14, delta is small and known (294's listener change the lead hypothesis for a semantics dependency) — mechanic triaging. rc.15 MAY NOT BE PROMOTED. The 279 RED proof run (33174142449) is dispatched into the freed fleet group. The honest scorecard across five candidates: every leg-1-4 failure mode eliminated and proven; the fleet went 26→34→33 green with every red root-caused within hours of firing; what remains is two fresh journals to read — and 296's diagnostics mean they were captured.
---

author: foreman
created: 2026-08-28 15:23
---
rc.16 CUT (v2026.08.0-rc.16, tag at 958a320b2, 2026-08-28 ~15:20Z) — sixth candidate, and the first with an EMPTY LEDGER: every red across five chains is root-caused with its fix aboard — 293's lottery, 227's SIGPIPE, 295's fixture pollution, 294's listener crash, 297's era collision (era-accurate bootstrap), 299's watchdog hole (bounded sub-attempts), 300's impatient assert — plus the wedge arc (279) riding its first gating fleet already RED-PROVEN (seen red against rc.09, seen green against master, closed). The architect's pre-declared-red condition dissolved when 299 froze before the cut assembled. Cut mechanics: the preflight demanded pg_regress at the exact tip (satisfied by its own named run 33183600615) and the pre-push images gate hit the unauthenticated-API rate limit — resolved by supplying GITHUB_TOKEN per the check's own designed path (the gate ran and verified, authenticated; 'OK: images green at 958a320b28b1'). Orchestrator 33184839982 in flight, watcher armed on the run id. THE CLAIM: 36/36 arcs, the first fully green chain — and if anything reds, it is a bug nobody has seen yet, arriving with its journal.
---
<!-- COMMENTS:END -->
