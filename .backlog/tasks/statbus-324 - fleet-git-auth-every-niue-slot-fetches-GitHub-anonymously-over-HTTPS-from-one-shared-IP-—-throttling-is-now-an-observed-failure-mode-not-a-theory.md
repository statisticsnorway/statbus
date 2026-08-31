---
id: STATBUS-324
title: >-
  fleet-git-auth: every niue slot fetches GitHub anonymously over HTTPS from one
  shared IP — throttling is now an observed failure mode, not a theory
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-31 11:17'
updated_date: '2026-08-31 12:54'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-31 12:36
---
Foreman (2026-08-31): 325 landed at 71ca22be5 → the two build items are unblocked and dispatched to the engineer: (1) GIT_TERMINAL_PROMPT=0 on the product's git invocations; (2) origin-to-HTTPS one-line repair in ./sb install's idempotent config work. Engineer also does the one confirming read of ci-notify.sh to close the no-git/curl/token thread.
---

author: foreman
created: 2026-08-31 12:45
---
Foreman (2026-08-31): both build items LANDED at 173ea514c (foreman-reviewed line by line, gofmt/vet/tests re-verified independently). Engineer's measured before/after REFUTES part of the ruling's premise: GIT_TERMINAL_PROMPT=0 changes only the trailing clause (Device not configured → terminal prompts disabled); git still leads with 'could not read Username', so the throttling-reads-as-auth misdiagnosis survives. The flag's honest value (hang removed, deterministic failure) is shipped. THIRD ITEM now before the architect: detection-and-translation in the fetch path (the ticket description's own 'detect the credential-prompt case and say what actually happened'). Also recorded: ci-notify.sh is 4 lines delegating to ./sb upgrade check — the anonymous GitHub API calls behind the 162.55.61.141 rate-limit failures live in the Go RunCheck path, giving the quota residual a precise home if it reopens. Ticket stays In Progress pending the architect's third-item ruling.
---

author: foreman
created: 2026-08-31 12:54
---
Foreman (2026-08-31): third item LANDED at 7473cddfb (reviewed; four tests re-verified by name, incl. the before/after-flag pair proving the flag alone was insufficient). One implementation at the site that owns git-failure formatting (runCommandOutputTimeout → explainGitFailure). KNOWN GAP on record: install.sh's own bootstrap fetch — the exact site of gh's observed failure — still shows raw git text; a bash copy would be the forbidden second translator, and on a truly fresh bootstrap ./sb doesn't exist yet. Ticket-or-accept verdict with the architect. 324 stays In Progress until that verdict; then closes.
---
<!-- COMMENTS:END -->
