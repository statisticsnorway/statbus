---
id: STATBUS-324
title: >-
  fleet-git-auth: every niue slot fetches GitHub anonymously over HTTPS from one
  shared IP — throttling is now an observed failure mode, not a theory
status: To Do
assignee:
  - architect
created_date: '2026-08-31 11:17'
updated_date: '2026-08-31 11:36'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Architect ruling (2026-08-31): the credential question largely DISSOLVES — with one recorded premise and one recorded residual.** The repo is PUBLIC and new boxes already clone over HTTPS (create-new-statbus-installation.sh:268; 283 removed per-slot keygen on the same evidence), so deploy keys/tokens would answer a question that should not exist. WHAT REMAINS, both small: (1) older boxes with SSH-era origins get a one-line origin-to-HTTPS repair folded into ./sb install's idempotent config work; (2) the REAL defect: set GIT_TERMINAL_PROMPT=0 on the product's git invocations so an unreachable/refused remote says 'could not reach github.com' instead of prompting for a username — a credential prompt at a failure moment teaches an operator that a network problem is an auth problem, and on an NSO box that misdiagnosis costs a support cycle. PREMISE ON RECORD: all of this holds while the repo is PUBLIC; if it ever goes private the design is void and credentials return. RESIDUAL RISK ON RECORD (foreman): the QUOTA half does not fully dissolve — gh's fetch was refused because GitHub throttles anonymous HTTPS by IP, and nine slots share niue's; accepted at normal cadence (the failing day was a seven-install burst), REOPENS if a throttle fires on an ordinary day. ci-notify.sh showed no git/curl/token usage in the architect's grep — one confirming read closes that thread. Build items → engineer's queue behind 325 (same git-invocation territory).
<!-- SECTION:NOTES:END -->
