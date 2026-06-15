---
id: STATBUS-056
title: >-
  harness-wait-for-images: discover-job preflight that waits for the per-commit
  service images before fan-out (STATBUS-025 follow-on)
status: To Do
assignee:
  - engineer
created_date: '2026-06-15 15:01'
updated_date: '2026-06-15 15:14'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PAUSED (foreman + engineer, 2026-06-15) — do NOT build speculatively. The actual STATBUS-025 build-sb failure was NOT the service images: it was dev.sh's preamble `./sb db seed fetch` being FATAL under set -e (dev.sh:77, the optional seed fetch called OUTSIDE install.go's graceful runSeedRestore wrapper). Fixed in commit 9f9a2b4e0 (make it non-fatal). The run died at the SEED before any scenario, so the service-image dependency this preflight guards has NOT actually been hit yet. Per 'test to know, don't gold-plate': build 056 ONLY IF a real run (with the seed-fix in) surfaces a service-image-pull 'manifest unknown' on the HEAD upgrade. For tonight, the operator's manual wait-for-Images (master) + dispatch-Images-on-red-ref (031 RED branch) cover the need. Engineer prepared but did NOT build it; assignee retained for if/when it's needed.

IMPLEMENTATION DETAIL captured (engineer built it, but the uncommitted diff was LOST to a backlog-MCP `reset: moving to HEAD` before it could be committed — 056 was being HELD per sequencing; lesson: commit agent diffs immediately, don't hold across task-edits). The design to REBUILD when needed: new final step in the discover job, 'Wait for the per-commit service images' — docker login ghcr (GITHUB_TOKEN, packages:read), poll `docker manifest inspect ghcr.io/statisticsnorway/statbus-{app,worker,db,PROXY}:<commit_short>` every 30s, budget 40m; commit_short=`git rev-parse --short=8 HEAD` (matches images.yaml's describe job; discover is github.sha-pinned so the tag is exact); all present->fan out, absent past budget->::error + actionable stderr + exit 1 (run-scenario skipped). Raise discover timeout-minutes 20->50. ENGINEER'S KEY CATCH (keep it): poll FOUR images incl. PROXY — caddy/docker-compose.yml interpolates statbus-proxy:${COMMIT_SHORT}, so the HEAD upgrade's `docker compose pull --profile all` resolves it too; gating only {app,worker,db} would let a scenario die at the proxy pull. (rest=postgrest is pinned, NOT per-commit; statbus-sb isn't harness-pulled — exclude both.) Do NOT gate on statbus-seed (optional; dev.sh fetch now non-fatal). REBUILD + commit-atomically before the comprehensive run (after 0-happy confirms).

CORRECTION + clean handling (2026-06-15): the preflight diff was NOT lost to a backlog reset (my misread of the reflog timing) — the engineer had FINISHED it before the pause landed and DELIBERATELY saved it to tmp/statbus-056-preflight.patch (88 lines, `git apply --check` passes) then reverted the working tree clean, to avoid a dangling uncommitted change in the shared harness workflow while the operator re-runs 0-happy + foreman cuts 031 RED off master. RE-APPLY IS ONE COMMAND when needed: `git apply tmp/statbus-056-preflight.patch` -> review -> commit (atomically). (Note on the backlog MCP `reset: moving to HEAD`: it is --mixed — unstages only, working-tree content survives, per the architect's repeated 'work intact, re-staged' experience — so it does NOT destroy uncommitted work; pathspec commits handle the unstaging fine.) Patch polls statbus-{app,worker,db,proxy}:<commit_short>, 40m budget, loud fail, discover timeout 20->50.
<!-- SECTION:NOTES:END -->
