---
id: STATBUS-056
title: >-
  harness-wait-for-images: discover-job preflight that waits for the per-commit
  service images before fan-out (STATBUS-025 follow-on)
status: In Progress
assignee:
  - engineer
created_date: '2026-06-15 15:01'
updated_date: '2026-06-15 15:02'
labels:
  - install-recovery
  - ci
  - harness
dependencies: []
priority: high
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DURABLE FIX for dispatch-validation racing the Images build (engineer design, 2026-06-15; surfaced when re-running 0-happy-upgrade to confirm the daemon-startup fix — "manifest unknown" on statbus-seed:<sha> because Images was still building).

ROOT MODEL (engineer-verified, corrects an earlier stale assumption): the `./sb db seed sync` command + the seed-existence preflight gate (50fd4325f) were RETIRED in 9ee422652 ("retire the git-publish distribution — the image is the sole seed source"; -1531 lines incl. seed_sync.go). Current model: per-commit images built by the master-push Images workflow are the sole source; there is no local seed rebuild/push command. images.yaml triggers on push:[master] + workflow_dispatch ONLY (no tags, no feature branches).

THE REAL HARD DEP IS THE SERVICE IMAGES, NOT THE SEED:
- SEED is OPTIONAL: install.go runSeedRestore (~1547) catches a missing-seed fetch -> "No seed available — will run all migrations" -> non-fatal (migrate up replays from scratch; only slower). (OPEN: build-sb's own seed pull in the harness appears to hard-fail on a missing seed — confirm via the failed-run image:tag grep and make it non-fatal too if so.)
- SERVICE images MANDATORY: the HEAD upgrade's applyPostSwap runs `docker compose pull --profile all` -> resolves statbus-{app,worker,db}:${COMMIT_SHORT} (docker-compose.{app,worker}.yml + postgres/docker-compose.yml). Required to run the upgraded stack; can't migrate-from-scratch around a missing app image. Built by the same master-only Images run.

THE FIX: add a wait-for-per-commit-images preflight to the harness DISCOVER job — after build-sb, before emitting the matrix, poll ghcr for statbus-{app,worker,db}:<commit_short> with a bounded budget (~30-40m; Images takes ~20-30m). Present -> fan out. Absent past budget -> fail discover LOUDLY with an actionable message ("images for <sha> not published; for a non-master ref, dispatch Images on it first: gh workflow run images.yaml --ref <branch>"). Self-contained in the harness workflow (no cross-workflow / release.go coupling). Replaces the operator's manual wait-for-Images with an automated, self-documenting gate; makes the comprehensive run + every future dispatch robust against the race + gives an actionable error instead of a cryptic per-scenario "manifest unknown".

OWNER: engineer (owns .github/workflows/install-recovery-harness.yaml). Engineer to prepare the diff; foreman commits it BEFORE the comprehensive run (after the in-flight 0-happy re-run confirms, so the preflight commit doesn't move the operator's current wait target mid-flight). For tonight's individual runs the operator's manual wait + dispatch-Images-on-red-ref covers it.
<!-- SECTION:DESCRIPTION:END -->
