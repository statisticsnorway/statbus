---
id: STATBUS-057
title: >-
  image-cleanup-gc-multiarch: weekly cleanup deletes referenced untagged
  per-arch manifests → breaks old commits' (releases') images → install/upgrade
  of old versions fails or local-builds
status: In Progress
assignee: []
created_date: '2026-06-15 16:38'
updated_date: '2026-06-16 09:49'
labels:
  - ci
  - images
  - reliability
  - product
dependencies: []
priority: high
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PINNED by engineer + foreman-verified (2026-06-15). A real PRODUCTION reliability bug, surfaced by the install-recovery harness (which installs an old baseline v2026.05.2 → its proxy image pull fails → ~35min local build → run timeouts).

THE DELETER: .github/workflows/image-cleanup.yaml — weekly (cron Sun 04:00 UTC) + workflow_dispatch; matrix [statbus-app,worker,db,proxy]; actions/delete-package-versions@v5 with min-versions-to-keep:20 + delete-only-untagged-versions:true.

THE BUG (mechanism — foreman-refined from the engineer's pin): the workflow's logic does NOT filter by v* (the header comment "Version-tagged images (v*) are kept indefinitely" is STALE + irrelevant — post-rc.63 images are tagged by COMMIT-SHORT, e.g. statbus-proxy:50fd4325, and the delete step keys on delete-only-untagged, never on v*). The actual failure: delete-only-untagged:true + keep-20 deletes the UNTAGGED per-arch manifests (+ config/layer blobs) that a multi-arch TAGGED image references. The tagged manifest list (proxy:50fd4325) survives but is BROKEN — it points at a deleted manifest digest. Observed pull error: "content at ghcr.io/.../statbus-proxy/manifests/sha256:638269... not found" (a referenced digest, not the tag). proxy crosses the keep-20 boundary FIRST (it accrues versions fastest) → proxy GC'd for v2026.05.2/.3/.4/.5 while app/db/worker:50fd4325 all survive (engineer verified via docker manifest inspect; ghcr public). The v2026.05.2 Images run ~10 days ago fully succeeded (proxy built+published) — then this cleanup pruned its referenced manifests.

PRODUCTION IMPACT: ANY install/upgrade that pulls an OLD commit's images (an older release, a rollback target, the harness baseline) hits broken/missing referenced manifests → docker compose pull fails → install.go falls back to a ~35-min LOCAL build (if build context present) or fails. The COMMON case (install/upgrade the LATEST release, images retained) is unaffected; the edge cases (old-release install, rollback to an aged version) break. North-Star-relevant (reliable unattended install/upgrade).

FIX OPTIONS (engineer to work out the precise one — CI-domain, multi-arch-aware):
1. Make the cleanup multi-arch-safe: do NOT delete untagged versions that are referenced by a surviving tagged manifest list (digest-aware retention). delete-package-versions@v5 may not support this directly — may need a custom ghcr-API cleanup that walks tag→manifest→referenced-digests and excludes them.
2. Resolve release TAGS (git rev-parse <tag>^{}) → keep ALL image versions (incl. untagged referenced manifests) for those commit-shorts. (Protects releases; doesn't protect arbitrary old commits.)
3. Raise min-versions-to-keep substantially (blunt; delays but doesn't eliminate; multi-arch accrues fast).
4. Fix the stale header comment regardless.
INTERIM (harness): 056-style baseline-image presence check (fail loud if a baseline image is missing) + the committed 120-min timeout (absorbs the local build) + optionally republish the GC'd baseline (gh workflow run images.yaml --ref v2026.05.2) before the comprehensive run.

OWNER: engineer (has the Images/CI context). Priority: HIGH (blocks the harness comprehensive run from being fast/reliable + is a latent production reliability bug).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
FOLLOW-UP FLAGS surfaced during the 057 fix (engineer, 2026-06-16) — recorded durably so they survive context-continue; DISCUSS the proper fix with King before acting:
1. FORWARD-LOOKING ONLY: the digest-aware cleanup PREVENTS future breakage but does NOT repair already-broken old tags. Concrete broken examples (children already deleted, 404 on pull): statbus-proxy:sha-744f8cce, statbus-proxy:sha-30865d75, statbus-proxy:sha-58f8fa87. Remediation = republish via `gh workflow run images.yaml --ref <tag-or-commit>`. DECISION NEEDED: which broken commits to republish (the harness baseline tag v2026.05.2 @ commit 50fd4325 at minimum?).
2. BEHAVIOR CHANGE (conscious ACK needed): replacing keep-20 with digest-aware retention means the cleanup now deletes ALL unreferenced untagged orphans older than the 7-day guard (more than before) — but NEVER a referenced one. Intended Option-1 behavior; confirm acceptable.
3. DELETE RESTRICTIONS: `gh api DELETE` can fail on GitHub's last-version / >5000-downloads restrictions; currently caught with `|| WARN` (logged, job continues). Confirm WARN-and-continue is the right policy vs hard-fail.

NOTE: the 057 fix itself was BOUNCED (foreman, 2026-06-16) for a fail-OPEN safety bug in fetch_children (a failed manifest fetch was swallowed by `|| true` → unprotected children → deletable on the cron). Bounced to fail-CLOSED (abort the run, delete nothing, on any unresolved tagged manifest) + real dry-run verification on live GHCR before commit.
<!-- SECTION:NOTES:END -->
