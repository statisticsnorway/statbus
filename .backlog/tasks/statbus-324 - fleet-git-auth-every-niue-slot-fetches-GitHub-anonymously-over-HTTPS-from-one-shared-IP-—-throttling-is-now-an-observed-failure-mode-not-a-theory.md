---
id: STATBUS-324
title: >-
  fleet-git-auth: every niue slot fetches GitHub anonymously over HTTPS from one
  shared IP — throttling is now an observed failure mode, not a theory
status: To Do
assignee:
  - architect
created_date: '2026-08-31 11:17'
labels:
  - ops
  - cloud
  - upgrade
dependencies: []
priority: medium
type: enhancement
ordinal: 317000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a box's ability to fetch its own upgrades never depends on how many of its neighbors fetched recently. Today it does: all niue slots share one egress IP (162.55.61.141) and fetch the public repo anonymously over HTTPS — and GitHub throttles anonymously by IP.

OBSERVED, twice in two days: (1) the Notify-cloud-services job failed for five slots with "API rate limit exceeded for 162.55.61.141" (2026-08-29, boxes' ci-notify.sh making anonymous API calls); (2) gh's v2026.08.0 bootstrap install died at git fetch with "could not read Username for 'https://github.com'" + "expected flush after ref listing" (2026-08-31) — GitHub refusing the anonymous request after a morning of fleet-wide fetches (six installs plus every box's discovery tick, ma's at 2-minute intervals) from the one IP; git's credential-prompt fallback then died on the promptless TTY. ua, minutes earlier, simply fit under the window.

THE SHAPE TO DESIGN (architect): authenticated git access per box — a read-only deploy key (SSH remote) or a scoped token — provisioned by create-new-statbus-installation.sh at birth and repaired by ./sb install for existing boxes; rotation story; and the same treatment for whatever ci-notify.sh still calls. Frame check: an NSO standalone box has its OWN IP and rarely fetches — this fragility is mostly OUR multi-tenant topology — but the failure text an operator sees ("could not read Username") is the product speaking gibberish at exactly a failure moment, so at minimum the fetch path should detect the credential-prompt case and say what actually happened.

Not urgent-tonight: the convergence run completes with waits-and-retries. Files the class so it dies in design, not in runbooks.

WHAT IS ACHIEVED: fleet fetches stop sharing one anonymous quota, and a throttled fetch names itself instead of asking a promptless box for a username.
<!-- SECTION:DESCRIPTION:END -->
