---
id: STATBUS-302
title: >-
  upgrade-probe-gh-dependency: status probes exec the gh CLI production boxes do
  not have — probe failure masquerades as build failure
status: In Progress
assignee:
  - '@architect'
created_date: '2026-08-28 16:24'
labels:
  - upgrade
  - cli
  - ops
dependencies: []
priority: high
type: bug
ordinal: 295000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: an NSO box must be able to report a candidate's build status using only what the product installs. Today the upgrade service's status probes shell out to the `gh` CLI — which production boxes do not have — so candidates show "images failed" / stuck "artifacts building" for reasons that are about the PROBE, not the images.

THE EVIDENCE (King's screenshots, 2026-08-28): demo.statbus.org and a second (unidentified) slot both show the verbatim error 'CI images absent after 20m0s timeout; gh probe err=exec: "gh": executable file not found in $PATH' against candidates whose images may be perfectly fine. VERIFIED IN CURRENT CODE, not just old binaries: service.go:1722 and :4322 run `gh api repos/.../actions/workflows/...` — the dependency is live at master.

WHY IT IS WRONG: (a) gh is not installed by ops/setup-ubuntu-lts-24.sh and never will be on an NSO box — the probe fails everywhere production runs; (b) even where gh exists, an unauthenticated fallback hits the shared-IP 60/hr quota (the 287/rate-limit family); (c) the failure is misattributed to the CANDIDATE ("CI image build failed") when it is the probe that could not run — a false verdict shown to an operator.

FIX SHAPE (architect to rule): the probes must use what the product already has — plain HTTPS. The release manifest is already fetched tokenlessly (FetchManifest); the image-existence question can be answered by a ghcr.io manifest HEAD (tokenless for public images) instead of asking GitHub Actions' API how the workflow felt. Where workflow-conclusion truly matters, the probe must degrade honestly: "could not determine build status (no gh CLI)" — never "images failed". Distinguish probe-failure from build-failure in both the row status and the UI text.

WHAT IS ACHIEVED: a candidate's status on an NSO box reflects the candidate, not the probe's toolchain; and no operator is told a build failed when nobody could check.
<!-- SECTION:DESCRIPTION:END -->
