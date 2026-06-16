---
id: STATBUS-063
title: >-
  repair-broken-release-images: one-off republish of stable-RELEASE images with
  pruned referenced manifests (releases only, NOT release candidates)
status: In Progress
assignee: []
created_date: '2026-06-16 10:00'
updated_date: '2026-06-16 10:38'
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
