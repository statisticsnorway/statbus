---
id: STATBUS-188
title: >-
  dev-db-crash-cycles: straggler kill -9 remediation correlates with postmaster
  crash recovery; crash-notice log lines missing
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-07-14 23:17'
updated_date: '2026-07-30 22:27'
labels:
  - testing
  - infrastructure
  - not-install-upgrade
dependencies: []
priority: medium
ordinal: 189000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the dev harness's own straggler remediation must never destabilize the shared dev database, and every postgres crash must leave its root-event evidence in reachable logs.

OBSERVED (2026-07-14 22:06-23:14 UTC, local dev db, container statbus-local-db Up 39h): THREE postgres crash-recovery cycles (22:06→22:24, 22:43→22:44, 23:14) during STATBUS-175 batch work. Initial read was macOS Docker memory pressure under heavy 401 import load. The third cycle sharpened it: mechanic's kill -9 on straggler pg_regress+psql PIDs (dev.sh's OWN documented remediation, via docker compose exec db) was followed within ~30s by recovery mode — 2-for-2 across incidents. Killing a pure CLIENT psql cannot cause postmaster crash recovery (backend sees EOF, aborts cleanly); only a BACKEND death can. Hypotheses: (a) PID reuse between pgrep and kill catching a backend; (b) the pgrep pattern ('pg_regress|HIDE_TABLEAM') matching more than clients; (c) coincidental OS/VM OOM kill of the import backend at cleanup time (Docker VM 15.6GiB).

SECOND ANOMALY: across the container's ENTIRE docker-log history there is NO 'server process was terminated by signal' / 'crash of another server process' line — postgres's standard crash-detection evidence is absent despite three recovery cycles, and the in-container collector file (/var/log/postgresql/postgresql-18-main.log) is EMPTY (0 lines). The postmaster's own log stream apparently goes nowhere reachable. Root-cause diagnosis is impossible without it.

CHAIN-STARTER, also in scope: 401's regeneration ran ~28 min and was killed by the runner's background-task timeout, leaving the straggler — recurring by construction for any test longer than the runner budget.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Postmaster log stream made reachable (crash-notice lines land in docker logs or a non-empty collector file) — no future crash without root-event evidence
- [ ] #2 The kill-then-recovery causality resolved with evidence (exact killed cmdlines / PID-reuse check / OOM evidence from the Docker VM), not pattern-matching
- [ ] #3 dev.sh straggler remediation re-ruled if implicated: safe kill order/signal (TERM to clients first, never blind -9 in the db container) documented in the BLOCKED-lock message
- [ ] #4 Long-test regeneration path documented so runner timeouts stop manufacturing stragglers (adequate timeout or detached run for 400/401-class tests)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-14 23:53
---
AC#2 EVIDENCE (mechanic's verbatim pgrep -af output from BOTH kill events, recorded before scrollback loss): both kill lists were PURE CLIENTS — pg_regress parent (/usr/lib/postgresql/18/lib/pgxs/src/test/regress/pg_regress --use-existing ... 401_import_jobs_for_brreg_selection) + its psql child (/usr/lib/postgresql/18/bin/psql -X -a -q -d test_401_... -v HIDE_TABLEAM=on ...). PIDs 33240/33246 (event 1, test DB ..._97365) and 33849/33855 (event 2, ..._66023) — different pairs, same shape. VERDICT ON THE HYPOTHESES: (b) pgrep-pattern-matched-a-backend is FALSIFIED (cmdlines are unambiguous clients). (a) PID-reuse-within-the-window remains possible but implausible twice consecutively. Surviving candidates: (c) coincidental OOM at cleanup time, or a NEW one worth testing under AC#2 — killing the psql client mid-29K-row import forces the server backend to ABORT a very large transaction; if the abort path spikes memory or hits a bug, the backend death would follow the client kill by seconds, exactly matching the observed ~30s correlation with NO backend in the kill list. AC#1 (make the postmaster log stream reachable) is the prerequisite for distinguishing these — the crash-notice line names the dead PID and signal.
---

author: foreman
created: 2026-07-29 11:05
---
SCOPE TRANSFER IN (foreman, 2026-07-29): the three remaining STATBUS-175 echo-suppression conversions (401, 402, 500) now ride THIS ticket as a finalization step, so 175 can close on its own completed work. Rationale: 401's ~28-minute expected-file regeneration is exactly the workload that triggered the crash cycles under investigation here (175 comments #4/#5) — re-attempting it before this ticket answers the infra questions would just reproduce the incident. Sequence: answer AC#1-#4 → then run the three conversions as the proof-of-fix workload (a successful 401 regeneration under the corrected infra is a natural acceptance run). The King may override this transfer during his review of this ticket.
---

author: foreman
created: 2026-07-29 16:43
---
NATURAL OCCURRENCE RECORD (foreman, 2026-07-29, from the 175 batch-3 regeneration): the mechanic's first regen attempt was EXTERNALLY killed mid-flight (he did not kill it; after test 309 completed, during 310) — the runner-timeout/external-kill class this ticket's AC#4 names, occurring naturally again. Chain: kill → orphaned pg_regress+psql pair in the db container → dev.sh's check_no_straggler_pg_regress guard REFUSED the next attempt by name (the STATBUS-158 protection working as designed) → orphan self-cleared within minutes → clean re-run. Notable for AC#3's re-rule: NO manual kill was needed — the orphan exited on its own, which supports 'report and wait' over kill -9 as the default remediation. Also notable: NO postmaster crash-recovery cycle followed this straggler episode (unlike the 07-14 incidents where recovery followed the kill -9 within ~30s, 2-for-2) — consistent with the hypothesis that the KILL, not the straggler, correlates with backend death. Evidence value: one more data point for the kill-causality question (AC#2), zero db mutation, all handled within standing orders.
---

author: foreman
created: 2026-07-30 22:20
---
KING-RULED TRACKING DESIGN (2026-07-31; foreman proposal, King: 'I agree', double-check completed): THE EVIDENCE HOLE IS OUR OWN FILTER. start-postgres.sh runs the db with log_min_messages=fatal by default (start-postgres.sh LOG_MIN_MESSAGES default + postgresql.conf:57); postgres emits its crash notices ('server process (PID n) was terminated by signal 9', 'automatic recovery in progress') at LOG severity, which sits BELOW fatal in the ordering — the postmaster reported every kill and the filter discarded exactly those lines. What we saw (recovery-mode refusals) are FATAL client messages: symptom passed, cause dropped. The empty collector file is a red herring (logging_collector=off is deliberate; stderr→docker logs is the correct container posture). THE DYNAMIC SWITCH EXISTS as the King recalled (DEBUG=true → INFO + auto_explain, start-postgres.sh:41-54) but it is two-position and both positions are wrong for crash tracking: quiet=crash-blind, loud=firehose. RULED FIX, three layers: (1) raise the QUIET floor fatal→log in BOTH places (one token each; admits exactly the LOG-class postmaster lines while ERROR/WARNING stay suppressed — severity ordering puts them below LOG; DEBUG switch untouched). FLEET-RELEVANT: postgres/postgresql.conf is the image config for every deployment — production boxes are equally crash-blind today. (2) dev.sh db crash-evidence — on-demand dumper: container cgroup memory.events oom_kill counter, Docker-VM dmesg extract, docker-logs tail, container inspect; evidence collection only, no standing daemon. (3) RED→GREEN probe on a THROWAWAY container (never the dev db): kill -9 a backend, assert the crash-notice line lands in docker logs — red under fatal, green under log; this is AC#1's oracle. THEN AC#2 resolves by controlled reproduction on the same throwaway rig (big import + client kill → does the backend's large-tx abort draw an OOM?). ASSIGNMENTS: mechanic builds layers 1+2; TESTER runs layer 3 and all subsequent test executions — per the King's serialization ruling (2026-07-30): the tester agent OWNS test-run execution, Erlang-style single ownership; AC#4's concrete shape = tester-owned execution + a right-sized/detached timeout for 400/401-class regenerations, which removes the straggler manufacturing step.
---

author: foreman
created: 2026-07-30 22:27
---
LAYERS 1+2 REVIEWED + COMMITTED b39bbf347 (foreman, 2026-07-31): the quiet floor is raised (fatal→log in start-postgres.sh's default AND postgresql.conf, WHY-comments in both, DEBUG branch untouched — diffs read in full) and `./dev.sh db crash-evidence` is live (read-only 4-part snapshot: logs tail / cgroup oom_kill counter / Docker-VM dmesg / inspect state incl. the RestartCount-is-top-level fix the mechanic caught himself; bash -n clean; smoke-run against the live dev db produced tmp/db-crash-evidence/20260730T222515Z.log, correctly surfacing the historical July-14 lines). NOTE: the running dev container still has the OLD filter until its next recreate — the new floor applies from the next container start. AC#1 checks ONLY on the tester's RED→GREEN probe: RED leg = the config at commit 87ca3aef9 (pre-fix, extracted via git show — pinned by SHA since HEAD has now moved), must show the crash line ABSENT under SHOW log_min_messages=fatal; GREEN leg = b39bbf347's config, line PRESENT verbatim. PROCESS VIOLATION RECORDED, corrected with the mechanic directly: he ran git stash/stash-pop on the SHARED tree for a shellcheck before/after comparison — teammates never touch git state, stash included (a stash sweeps ALL agents' in-flight work off disk; a pop conflict would have been unrecoverable mid-flight). Tree verified intact after the fact (his 3 files only; no stash residue — the 33 listed stashes are months-old historical entries). The correct tool for before/after comparison is `git show <sha>:<file>` into a scratch dir — read-only, no shared state touched.
---
<!-- COMMENTS:END -->
