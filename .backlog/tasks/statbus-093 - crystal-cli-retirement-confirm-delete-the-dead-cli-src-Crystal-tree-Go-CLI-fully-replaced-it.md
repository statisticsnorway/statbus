---
id: STATBUS-093
title: >-
  crystal-cli-retirement: confirm + delete the dead cli/src/ Crystal tree (Go
  CLI fully replaced it)
status: To Do
assignee: []
created_date: '2026-06-18 17:05'
updated_date: '2026-07-03 10:45'
labels:
  - tooling
  - not-install-upgrade
dependencies: []
ordinal: 93000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: dead code can't mislead.
> BENEFIT: the retired Crystal tree — which has already misdirected root-cause analysis twice (dead Caddy templates read as live) — is confirmed unreferenced and deleted; nobody pays that tax a third time.
> STAGE: Hygiene.
> COMPLEXITY: mechanic-simple (confirm zero build-path references, git rm, doc sweep); foreman commits.
> DEPENDS ON: nothing.

---

The Go CLI (cli/internal/ + cli/cmd/, the `sb` binary) replaced the legacy Crystal CLI (cli/src/ — manage.cr + manage-statbus.sh; the .sh wrapper was already deleted). The mechanic verified (2026-06-18, during STATBUS-089) that nothing OUTSIDE cli/src/ builds or imports it: external mentions are only doc references + Go source comments ("Ported from Crystal cli/src/manage.cr") + the separate `n/` worker tree. The dead cli/src/templates/*.caddyfile.ecr were already deleted in commit 14b792318 because they twice misled a root-cause analysis into reading dead code (the live templates are caddy/templates/*.caddyfile.tmpl, rendered by cli/internal/config/config.go).

DO:
1. Confirm the Crystal CLI is fully retired — no build path, Makefile, CI workflow, dev.sh, or `sb` wrapper invokes cli/src/ or uses cli/shard.yml / cli/shard.lock.
2. If confirmed dead, `git rm` the cli/src/ tree (+ cli/shard.yml, cli/shard.lock if unused).
3. Sweep any remaining stale doc/comment references to the Crystal CLI.

Hygiene / footgun-removal (dead code mistaken for live). NOT on the framework critical path. Low priority. Foreman reviews + commits the deletion (agents stage + verify).
<!-- SECTION:DESCRIPTION:END -->
