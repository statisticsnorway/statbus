---
id: STATBUS-063
title: >-
  repair-broken-release-images: one-off republish of stable-RELEASE images with
  pruned referenced manifests (releases only, NOT release candidates)
status: In Progress
assignee: []
created_date: '2026-06-16 10:00'
updated_date: '2026-06-16 10:49'
labels:
  - ci
  - images
  - reliability
  - one-off
dependencies: []
priority: medium
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King-approved 2026-06-16: a QUICK ONE-OFF repair (operator), then never think about it again. Sibling of STATBUS-057 (which PREVENTS future breakage; this REPAIRS already-broken images).

## Scope (King's explicit constraint)
RELEASE images ONLY — stable ReleaseTags (e.g. v2026.05.2). NOT release candidates (v…-rc.N) and NOT arbitrary CommitShort tags. Rationale: stable releases are the durable artifacts real deployments install/roll back to; RCs are ephemeral test artifacts not worth repairing.

## The damage (concrete)
The old keep-20 cleanup pruned untagged per-arch child manifests referenced by surviving tagged multi-arch indexes → `docker pull` of those images 404s on a referenced child digest. Immediate one that matters: the harness baseline release tag v2026.05.2 → commit 50fd4325 (its statbus-proxy image children pruned → ~35min local-build fallback in the harness).

## The fix (one-off, operator)
For each STABLE ReleaseTag (vYYYY.MM.patch with NO -rc/-suffix) whose multi-arch images have missing referenced children: republish via `gh workflow run images.yaml --ref <ReleaseTag>`. Verify post-republish: `docker pull` of each repaired release succeeds + `docker manifest inspect` shows all referenced children present. Start with v2026.05.2.

## Done when
Every stable-release image pulls cleanly (no missing referenced child manifests); run once, close. (RCs intentionally left alone.)
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DISPATCH RESULT (operator + foreman-verified 2026-06-16): v2026.05.2 (harness baseline, commit 50fd4325) REPUBLISHED + verified OK (run 27611751266). v2026.05.1/.3/.4/.5 republished (runs 27611820926/824445/827804/831233) — foreman verified these runs have IDENTICAL job graphs to the working 05.2 run (describe → build app/worker/db/proxy × amd64+arm64 → manifest ×4, all success), so they genuinely rebuilt + pushed; the operator's initial 404s were premature checks (GHCR propagation lag, runs completed ~10:43Z). Operator re-verifying. v2026.03.0/.1 + v2026.05.0 = OUT OF SCOPE: predate the workflow_dispatch trigger in images.yaml (`gh workflow run` can't dispatch them); ancient + unlikely rollback targets + the harness doesn't use them. The CRITICAL baseline (v2026.05.2) is fixed; harness also protected by the 120-min timeout + STATBUS-056 baseline-presence check + STATBUS-057 future-breakage prevention. Close once operator confirms 05.1/.3/.4/.5 re-verify OK.
<!-- SECTION:NOTES:END -->
