---
id: STATBUS-129
title: >-
  init-db-on-error-stop: ON_ERROR_STOP=1 on all init-db.sh psql heredocs —
  silent per-statement failure class
status: To Do
assignee: []
created_date: '2026-07-03 19:22'
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
