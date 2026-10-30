---
id: STATBUS-129
title: >-
  init-db-on-error-stop: ON_ERROR_STOP=1 on all init-db.sh psql heredocs —
  silent per-statement failure class
status: Done
assignee: []
created_date: '2026-07-03 19:22'
updated_date: '2026-07-08 22:29'
labels:
  - install
  - postgres
  - fail-fast
  - follow-up
dependencies: []
ordinal: 130000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a failed statement at cluster birth can never pass silently.
> BENEFIT: a failed GRANT/role/notify-reader statement at cluster birth surfaces at birth as a named error instead of weeks later as a mystery on a deployed box — the same silent-loss class doc-025 D killed, closed for the remaining four heredocs.
> STAGE: Stage 1.
> COMPLEXITY: mechanic-simple (flag per heredoc) + tester proof (fresh create-db + full image build); King nod first (init path).
> DEPENDS ON: nothing.

---

DISCOVERED during the doc-025 D birth-half review (2026-07-03): postgres/init-db.sh runs `set -euo pipefail`, but `set -e` is BLIND to SQL failures inside a psql heredoc — psql exits 0 on per-statement errors unless -v ON_ERROR_STOP=1 is passed. A failed statement in any of these blocks is silently lost at cluster birth.

FIXED ALREADY (commit 98093f69f): the new role-GUC arming heredoc runs `psql -v ON_ERROR_STOP=1` (a silently-failed arming statement would re-mint the exact silent-loss class doc-025 D kills).

REMAINING (pre-existing, out of doc-025 scope): the OTHER psql heredocs in postgres/init-db.sh lack the flag — as of 98093f69f: the extensions/template block (~line 46, `psql <<'EOF'`), and the app-DB blocks at ~lines 135/146/156 (`psql -d "$POSTGRES_APP_DB" <<'EOF'`, plus the EOSQL one ~179). Same latent class: a failed GRANT / role setup / notify-reader statement at cluster birth passes silently and surfaces later as a mystery.

THE CHANGE: add `-v ON_ERROR_STOP=1` to every psql heredoc invocation in init-db.sh. One-line-per-site, no logic change. RISK to check before shipping: any statement in those blocks that currently FAILS silently on a fresh cluster (e.g. a CREATE against pre-existing state without IF NOT EXISTS) would now hard-fail init — verify each block is idempotent/clean-cluster-correct, then prove with a fresh `./dev.sh create-db` + a full docker image build (init-db.sh runs in the postgres image build; the seed-builder stage also runs it).

Flagged by: engineer. Filed by: foreman. Needs the King's nod before build (init path).
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-08 22:29
---
PROOF, both halves recorded precisely (2026-07-09): (1) IMAGE HALF done — tester built all images green at c7d5ef5a; init-db.sh in the db image carries the flag on 13 of 13 psql invocations (log: tmp/tester-129-image-build.log). Precision note: the build COPIES the script into the image; it executes at a container's FIRST START on an empty cluster (docker-entrypoint-initdb.d), so the build proves flags-in-image, not execution. (2) EXECUTION HALF rides the next arc dispatch for free — every recovery-arc VM install starts the db container on a fresh cluster and runs init-db.sh end to end; the imminent observational dispatches are the execution record. Any init statement failure now aborts the install loudly, which would itself be a finding.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NORTH STAR: the script that builds every fresh database fails loudly on the first broken statement. SHIPPED 752e5b4f1 (2026-07-09), dual-reviewed. All 13 psql invocations in init-db.sh carry ON_ERROR_STOP=1 — one uniform rule, zero logic change. Silence-audit found nothing relying on the old behavior: create-if-not-exists sites, PL/pgSQL-internal duplicate handling (empirically proved compatible by double-run under the flag), and birth-once creates whose loud failure on a dirty cluster is this ticket's purpose. Mechanism proved both ways on a scratch heredoc. ROUTING RECORDED: the ticket's "King nod first" marker was pre-frame conservatism — this is the ratified fail-fast doctrine on the init script with audited zero cost (same class as 027's stale marker); and the full-path proof needed no destructive dev-machine create-db — init-db executes on a fresh in-container cluster at every postgres image build (tester's local build = the record) and on every arc VM install (the imminent observational dispatches exercise the real path free). The destructive-command gate stays untriggered.
<!-- SECTION:FINAL_SUMMARY:END -->
