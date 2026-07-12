---
id: STATBUS-162
title: >-
  pg-regress-db-log-artifact: archive the db container's logs on failure so
  init-db aborts are readable after the fact
status: Done
assignee:
  - mechanic
created_date: '2026-07-12 03:39'
updated_date: '2026-07-12 04:17'
labels:
  - ci
  - testing
  - tooling
dependencies: []
references:
  - STATBUS-151
  - STATBUS-155
priority: low
ordinal: 163000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every red pg_regress run is self-sufficient evidence — the db container's own output (including init-db's [N/8] section markers) survives the run, without needing a kept environment.
> STAGE: CI diagnosability. FOUND: 2026-07-12 — the STATBUS-151 investigation could not read which init-db section aborted in four failing runs because the markers print to the db container's stderr, the Actions log carries only compose lifecycle, the containers were ephemeral, and no artifact was archived; one upload step would have decided that investigation in minutes (the adjudication's words).
> COMPLEXITY: mechanic-simple.

THE SHAPE (architect, 2026-07-12): on failure, the pg_regress workflow uploads the db container's logs (docker compose logs db) as a workflow artifact, modest retention. Composes with the STATBUS-155 principle: every red run self-sufficient, no hand-tracing from destroyed environments.

Origin: STATBUS-151 final adjudication, evidence-gap finding.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A failing pg_regress run's artifacts include the db container's logs (init-db markers readable)
- [x] #2 Green runs upload nothing extra (failure-only, modest retention)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-12 04:16
---
REDESIGN + RETIREMENT CONDITION (architect review, 2026-07-12). The ruled artifact-fetch shape proved IMPOSSIBLE against two verified constraints: niue's sshdoers locks the CI key to exactly one command line (any second SSH command rejected), and that command's own EXIT trap removes the db container (compose down --remove-orphans) before any post-hoc fetch could run. APPROVED redesign: the failure path prints the db logs in-band — the EXIT trap dumps `docker compose logs db --tail=5000` inside STATBUS-162 delimiters (bounded AT THE PRODUCER per no-silent-caps: the GHA step-output ceiling truncates silently at the consumer, and a clipped BEGIN marker would lose everything; the tail window always holds a complete failure cycle since a failed init reprints its whole [N/8] sequence every boot under restart:unless-stopped) — and the workflow (ssh-action bumped v1.2.0→v1.2.1 for capture_stdout, tag + action.yml verified via the GitHub API) extracts the delimited section runner-side (env: indirection, injection-safe) and uploads it failure-only, 14-day retention. NAMED RETIREMENT CONDITION (the r19 pattern applied to harness complexity): when STATBUS-069 Phase-3 moves pg_regress onto the niue self-hosted runner, the capture_stdout pipeline RETIRES — replace with a direct docker compose logs artifact step. Ship-now over defer was ruled explicitly: the 151 investigation is the demonstrated price of every week without this.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SHIPPED d49f60244 (2026-07-12), dev.sh + pg_regress.yaml, +76/−2, architect SHIP with the bounded-tail fix applied. Full redesign story in comment #1: the ruled fetch shape was IMPOSSIBLE (one-command sshdoers lock + the trap removes the container), so the evidence leaves IN-BAND — the CI teardown trap prints docker compose logs db --tail=5000 inside STATBUS-162 delimiters on failure BEFORE delete-db (bounded at the producer per no-silent-caps; the header names the bound; a failed init reprints its whole [N/8] sequence every boot so the tail always holds a complete cycle); the workflow captures remote stdout (ssh-action v1.2.0→v1.2.1, tag + action.yml verified via the GitHub API), extracts the delimited section runner-side (env: indirection — untrusted remote output never interpolated into a script body; prefix-match BEGIN marker after the mechanic caught that the bound-annotated marker would have silently broken the exact-match regex — self-caught, the exact failure class this ticket kills), and uploads failure-only, 14-day retention, if-no-files-found: warn. AC#2 structural (if: failure() on all three new steps). VERIFICATION: bash -n, shellcheck per-finding diff (zero new), actionlint, YAML parse, and the awk extraction proven on synthetic input including the no-markers fallback; the full end-to-end is honestly deferred to the next ORGANIC red run (a red cannot be cheaply forced) — same pattern as 157's fast-path oracle. RETIREMENT CONDITION on comment #1: retires for a direct log-artifact step when STATBUS-069 Phase-3 moves pg_regress onto the niue self-hosted runner.
<!-- SECTION:FINAL_SUMMARY:END -->
