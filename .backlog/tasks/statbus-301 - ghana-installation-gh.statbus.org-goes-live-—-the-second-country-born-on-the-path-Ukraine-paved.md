---
id: STATBUS-301
title: >-
  ghana-installation: gh.statbus.org goes live — the second country, born on the
  path Ukraine paved
status: In Progress
assignee:
  - '@operator'
created_date: '2026-08-28 16:18'
labels:
  - ops
  - cloud
dependencies: []
priority: high
type: task
ordinal: 294000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: Ghana's statistical office gets a production StatBus at https://gh.statbus.org, provisioned by the exact mechanism every installation uses, born on the stable channel — the second country installed under the new creation path, and the first to benefit from everything Ukraine's maiden run taught us.

ALREADY IN PLACE: DNS for gh.statbus.org (King, 2026-08-28).

THE PROCEDURE (Ukraine precedent, plus the fixes its birth defects produced — all landed under STATBUS-283):
1. On niue, run ops/create-new-statbus-installation.sh with slot code `gh`, a NAMED version (never master — the list is the offer), and UPGRADE_ROLE=production (channel=stable derives from it; write NO UPGRADE_CHANNEL key — role only, per the 254/297 record).
2. Offset allocation is a HOST fact decided at creation time from niue's live slot table (ua took 10; do not guess from the board — read the host).
3. The script post-283 does the rest correctly by construction: tail delegates to install.sh at the named version (binary procured from the commit-tagged image — Ukraine's binary gap cannot recur; re-runs are probe-ladder no-ops, never data loss), HTTPS clone (tokenless git-tag discovery), and the host Caddy validate-then-reload as the FATAL last root-side step (Ukraine's dark-front-door cannot recur silently — a failed validate leaves the other countries served and the script loudly red).
4. Users: create the admin from .users.yml on the box.

PRIVACY CONSTRAINT, identical to Ukraine's and non-negotiable: the admin user's name and email are NEVER written to this ticket, the board, git, GitHub, or any persisted artifact. They exist only in the box's untracked .users.yml. The King supplies them at execution time through an unpersisted channel.

VERSION: the newest fully-verified candidate at execution time — default is v2026.08.0-rc.16 contingent on its chain verdict (in flight at filing), or the promoted stable if promotion has happened by then. The King may name a different version; whatever is installed, the box's role=production means it follows stable thereafter.

VERIFICATION AT COMPLETION (pin results here, no personal data): https://gh.statbus.org serves over TLS; ./sb --version reports the named version and commit; the upgrade service is active with channel=stable; upgrade discovery lists tags (pure git, no token); admin login works (verified by the human who holds the credentials, reported as pass/fail only).

BIRTH RECORD to pin on completion: version + commit installed, slot code, offset, date — the concrete named artifacts, nothing else.
<!-- SECTION:DESCRIPTION:END -->
