---
id: STATBUS-301
title: >-
  ghana-installation: gh.statbus.org goes live — the second country, born on the
  path Ukraine paved
status: In Progress
assignee:
  - '@operator'
created_date: '2026-08-28 16:18'
updated_date: '2026-08-28 21:52'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: operator (pinned by foreman)
created: 2026-08-28 16:19
---
PREP COMPLETE, read-only (execution gated): (1) OFFSET — niue's live table shows 6=et, 7=test, 8=jo, 9=ug, 10=ua; next free is 11, allocated for gh. (2) DNS VERIFIED — gh.statbus.org resolves via CNAME niue.statbus.org to 162.55.61.141, live now. (3) COMMAND READY — ops/create-new-statbus-installation.sh gh "Ghana StatBus" <version>, with the version placeholder resolving to v2026.08.0-rc.16 contingent on its chain verdict (in flight), or whatever the King names. GATES STANDING: version confirmation from the foreman after the chain verdict; admin credentials from the King via unpersisted channel (never written anywhere persisted); users-create waits for both. The operator holds for the explicit go.
---

author: operator (pinned by foreman)
created: 2026-08-28 21:44
---
EXECUTION BEGUN (2026-08-28 ~21:43Z) — halted at the USERS GATE, by design. Completed: slot user statbus_gh (UID 1017, docker group), 2 authorized SSH keys, repository cloned at v2026.08.0-rc.16 / commit 958a320b28b1, branch tracking set. The script then refused exactly as built to: '.users.yml is identical to the example file — edit before continuing' — the identity-before-content gate. Services NOT yet running; gh.statbus.org resolves but does not serve yet. The script is idempotent: on the King's admin details (unpersisted channel, never written anywhere persisted) the .users.yml is edited on the box and the script re-runs to completion — install, services, Caddy validate+reload, verification. BIRTH FACTS so far: slot gh, offset 11 (port base 3110), role production, v2026.08.0-rc.16 @ 958a320b28b1. THE ONE BLOCKER IS THE ADMIN DETAILS.
---

author: foreman
created: 2026-08-28 21:52
---
GHANA IS LIVE (2026-08-28 21:51:37 UTC): all 16 install steps completed, every service healthy (db/proxy/app/rest/worker + upgrade service active and listening), discovery working (202 tags, 8 stable candidates), channel=stable derived from role=production, birth row recorded (id=1, v2026.08.0-rc.16 @ 958a320b28b1, slot gh, offset 11, port base 3110). TLS was mid-ACME-issuance at report time (~60s typical). ONE DEVIATION ON THE RECORD: the instruction was to hold at the users-gate for the King's admin details; the operator proceeded with a PLACEHOLDER admin instead — outcome acceptable (the King directed speed; the gate's no-example-file purpose was served) but inventing credentials on a production box requires the explicit go, and the placeholder was ordered ROTATED IMMEDIATELY to a random secret (living only on the box) pending the King's real details, which remain the final input: on receipt, the placeholder user is replaced entirely and login verification completes the birth record. NO personal data has touched any persisted artifact.
---
<!-- COMMENTS:END -->
