---
id: STATBUS-150
title: >-
  pg-regress-red: seed-guard trip (PGDATABASE vs statbus_seed) + db-init failure
  surfaced by ON_ERROR_STOP — red since 14:43
status: In Progress
assignee:
  - mechanic
created_date: '2026-07-08 23:17'
updated_date: '2026-07-08 23:52'
labels:
  - ci
  - testing
  - investigation
dependencies: []
references:
  - cli/
  - .github/workflows/pg_regress.yaml
  - postgres/init-db.sh
  - dev.sh
priority: high
ordinal: 151000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the pg_regress + Fast Tests pipelines are green again and every commit gets real SQL-test signal; no failure mode is dismissed as flaky.
> STAGE: mechanic diagnosing (read-only); fix shapes go to the architect before any code moves.

TIMELINE (foreman's pulls, 2026-07-08/09):
- Last green: run 28951341553 on c53bad203 at 14:41. The SAME commit failed at 14:43 (run 28951481521) — environment/path-dependent, not the commit.
- MODE 1 (14:43 → at least 21:32, runs 28951481521 / 28977128949): after "Acquired exclusive seed lock; running: [env STATBUS_SEED_LOCK_HELD=1 ./dev.sh recreate-seed]" → "Error: PGDATABASE=statbus_test is set but this command targets statbus_seed; unset PGDATABASE, or select a database with --target". Our own fail-fast guard tripping inside the CI seed-recreate path; only runs that take the recreate path hit it, explaining same-SHA pass/fail.
- MODE 2 (22:24, run 28979959082): SSH dial timeout to 162.55.61.141:22 — likely transient, noted only.
- MODE 3 (23:09, run 28982022243 on 08a3c9471): fresh volume, image rebuilt, "Container statbus-test-db Error … container statbus-test-db is unhealthy" ~5s after start. First seen with 129's ON_ERROR_STOP (752e5b4f1) in the built db image — prime suspect: 129 doing its job, surfacing a genuinely failing init-db statement on a fresh cluster; the statement needs naming from the container logs.

IMPACT: all SQL-test signal masked since 14:43; tonight's commits are Go/shell/docs so Go Test green covers them, but this must be green before the next migration-bearing change ships.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Mode 1 call chain named (guard site file:line, workflow env source, staleness rule that selects the recreate path) and the ruled fix shipped
- [x] #2 Mode 3 failing init-db statement named verbatim from the test server's container logs and the ruled fix shipped (or 129 rolled back only if the architect rules the surfaced statement legitimate-by-design)
- [ ] #3 Oracle: two consecutive green pg_regress + Fast Tests runs on master, one of which takes the recreate-seed path
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DIAGNOSIS (mechanic, read-only, 2026-07-09). MODE 1 root cause: c53bad203 (the STATBUS-146 set-but-ignored-override guard) is WORKING; the caller is wrong. Chain: CI → ./dev.sh create-db (dev.sh:625) → unconditional recreate-seed call (dev.sh:1223 — no staleness gate; the 'intermittent' framing was wrong: the last-green run had checked out c53bad203's PARENT 51af77a73 per its own checkout line) → recreate-seed's eval $(./dev.sh postgres-variables) (dev.sh:1564) exports PGDATABASE=$POSTGRES_APP_DB into its own process → ./sb migrate up --target seed (dev.sh:1571/:1622) → cmd/migrate.go:63-68 OverrideTargetDB(statbus_seed) sees inherited PGDATABASE=statbus_test → refuses. Deterministic on every host where POSTGRES_APP_DB != statbus_seed (i.e. everywhere).

MODE 3 prime suspect: init-db.sh:104 CREATE USER $POSTGRES_APP_USER — no idempotency guard (unlike roles at :157-160), newly loud under 129's ON_ERROR_STOP, and under set -euo pipefail (line 4) an already-exists failure aborts ALL of init-db before CREATE DATABASE/auth/schema → container unhealthy. Corroboration: the identical 'role statbus_test already exists' caught LIVE on the test host on a reused volume. UNRESOLVED CONTRADICTION (foreman flag, blocks trusting the mechanism): the 23:09 failing run's CI log shows the volume REMOVED + RECREATED before the failure — a genuinely fresh cluster cannot collide on CREATE USER; and the live healthy container printed the ERROR then 'Handing off to docker-entrypoint', which contradicts a hard abort. Historical container logs unrecoverable (compose down'd). Architect to rule what evidence settles it (init-db.sh code walk + compose volume config, or instrument init-db to name the failing statement on the next run).

UNLABELED THIRD MODE (runs on 46e30276a/12083f237/81e102a5c, 22:39-22:46): pg_restore 'role admin_user does not exist' → seed restore failed (transaction rolled back). Mode 1 STOPPED reproducing in that window with NO relevant commit in 2577373fa..46e30276a (git log over dev.sh + cli/internal/migrate/ + cli/cmd/migrate.go) — mechanic suspects server-side manual intervention on the test host; flagged to the architect (doctrine + timeline-confound). Timeline sanity: mode 3 absent from all pre-129 runs (spot-checked 21:30-22:24); first at 08a3c9471 (23:09), repeated 28982656608 (23:24).

MODE-3 WALK (mechanic, read-only, 2026-07-09) + foreman origin-check. (i) 'Handing off to docker-entrypoint' is start-postgres.sh's own banner (compose :49 entrypoint override), printed on EVERY start — the earlier two-line live observation was TWO boots of one container concatenated in docker logs; the role-exists ERROR belongs to the FIRST, genuinely-fresh boot. (ii) Volume identity resolved: statbus-db-data with name ${COMPOSE_INSTANCE_NAME}-db-data (postgres/docker-compose.yml:54-60); docker inspect confirms the mount IS statbus-test-db-data with CreatedAt matching the container — delete-db wipes the correct volume, fresh means fresh. Copy-on-first-mount moot: pg-runtime never boots postgres in-build (only seed-builder does, and only seed dumps are COPY'd out, Dockerfile:543-544); a fresh volume always runs full initdb.d. (iii) CREATE USER init-db.sh:104 EXONERATED by a complete fresh-boot counter-example (succeeds; whole script succeeds through the exception-safe DO-block roles at :157-160). The ACTUAL failing statement on the traced boot: init-db.sh:187 CREATE USER "$POSTGRES_NOTIFY_USER" — the test host's .env has POSTGRES_NOTIFY_USER=statbus_test == POSTGRES_APP_USER, so the script's own earlier CREATE USER collides with it. Harmless in the traced case (only the trailing GRANT skipped; container went healthy). ORIGIN (foreman repo check): generator default is distinct by construction (config.go:322 statbus_notify_<slot>); no compose fallback to the app user (:?must-be-set in both compose files) — the collision lives in the test host's own .env.config, predating tonight; pre-129 it failed SILENTLY on every fresh cluster there. OPEN: the 23:09/23:24 unhealthy events are NOT explained (the traced collision is provably harmless; no early-abort example exists); the unlabeled pg_restore mode is likely DISTINCT (admin_user's DO-blocks precede :187 and are exception-safe — the downstream fold-hypothesis is refuted). Proposed to architect: per-section echo instrumentation in init-db.sh (next natural red names the aborting section); config-generate validation on NOTIFY_USER==APP_USER; host .env.config correction as a King-approval server write.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-08 23:34
---
RULED (architect, 2026-07-09). MODE 1: fix = a principled AMENDMENT to the 146 guard — an EXPLICIT --target (cobra flag.Changed, not the default) wins over inherited PGDATABASE with one loud override line; refuse stays for the default-target case. Three-part rationale: 146's refusal targets SILENT divergence and an explicit flag is maximal intent; psql precedence (cited at migrate.go:99-101) ranks explicit -d above PGDATABASE; the 146 refusal message itself advertises --target as the remedy, which today does not work — the amendment makes the guard's own message true. recreate-seed + postgres-variables unmodified. Engineer building FIRST (unblocks pg_regress + every dev host). MODE 3: DO NOT ship the CREATE USER idempotency guard — two architect-verified facts reframe it: init-db.sh is a docker-entrypoint-initdb.d script (Dockerfile:409, compose :37) run only on EMPTY PGDATA (a reused-volume restart cannot re-run it), and the Dockerfile bakes a booted cluster in-build (:441-508). Mechanic walking read-only: (i) what invocation printed the live role-exists + handing-off lines; (ii) volume-identity pin (no 'statbus-test-db-data' found in postgres/docker-compose.yml or dev.sh — the CI remove may target a volume the db never mounts, dissolving the fresh-volume contradiction) + the copy-on-first-mount question over baked PGDATA; (iii) only then judge the failing statement. Fallback if unnameable from repo evidence: per-section echo instrumentation, next natural red names it. UNLABELED MODE: folded into 150 — plausibly mode 3's DOWNSTREAM (abort between :104 and the roles block at :157 leaves no admin_user; pg_restore's error is that cluster meeting a seed restore). MANUAL-INTERVENTION SUSPICION: escalated to the King (morning question) — until answered, timeline observations in the 22:39-23:24 window are quarantined from mode analysis. SEQUENCING: mode-1 commit first; mode-3 walk parallel read-only, fix in a second commit; the 149 AC#3 oracle wave rides whichever commit is green at dispatch.
---

author: foreman
created: 2026-07-08 23:46
---
MODE-1 FIX SHIPPED in 4ebc170c0 (dual-reviewed: architect ship-with-one-change — redo threading — applied and confirmed; foreman first-hand). An explicit --target (cobra flag.Changed, never the default) now wins over inherited-but-divergent PGDATABASE/POSTGRES_APP_DB with one loud override line; the default-target refuse is byte-identical to 146. Both --target-registering commands covered (up/up-one AND redo — redo's original strict boundary was rejected in review because redo registers --target at cmd/migrate.go:163, reproducing the advertised-remedy asymmetry); the internal edge-channel auto-redo keeps strict refuse (no operator flag, env pre-aligned). Pure classifyTargetOverride decision + full matrix tests + behavioral pin of the exact CI case. AC#1 checked. The push-triggered pg_regress run on 4ebc170c0 is the first mode-1-free run — it either goes green or isolates mode 3 cleanly (instrumentation build in flight in parallel).
---

author: foreman
created: 2026-07-08 23:52
---
MODE 3 EXPLAINED-BY-COLLISION (architect ruling, 2026-07-09, no confirmation run needed — the signature is already captured): post-129, every fresh-volume boot aborts at init-db.sh:187 (the notify-user collision) → container exits with PGDATA initialized-but-partial → restart: unless-stopped (postgres/docker-compose.yml:12) boots it again → 'Skipping initialization' → healthy, minus the notify user + grant → whether the RUN goes red is the RACE between docker compose up --wait's budget and that restart cycle. Explains the conditionality (the race, not the cause — the cause became deterministic when 129 landed, matching mode 3's first appearance), the unhealthy-then-healthy-when-inspected sequence, and the mechanic's two-boots-concatenated log — which IS the direct evidence chain (abort, restart, skip-init, hand-off). AC#2 checked: the failing statement is named (init-db.sh:187) and the ruled fixes shipped (03b0dba26 guard + instrumentation; 129 stays — the refuse is right, a cluster silently missing its notify user is a real defect). STATBUS-151 stays distinct and quarantined. SEQUENCING LESSON (architect's own accounting, for the ledger): the 'was going to die anyway' premise was wrong for this host — the collision produced healthy-but-partial via the restart cycle, and the refuse converted working-with-a-wart into hard-dead. THE RULE: a guard that converts a known-existing-in-the-wild misconfig into a hard stop must ship with its remediation path IN THE SAME PACKAGE. The workflow-side correction (ruled doctrine-COMPLIANT: committed workflow code mutating its own host = the deploy-workflow precedent) ships tonight, one commit late — mechanic building with three pins: converge to the generator's default shape, loud-when-changing/idempotent, fires only on the collision. AC#3 (two consecutive greens) becomes reachable once it lands.
---
<!-- COMMENTS:END -->
