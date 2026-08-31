---
id: STATBUS-326
title: >-
  docdb-table-comments: doc/db table pages never render COMMENT ON TABLE — the
  audit surface hides exactly the notes written for auditors
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-08-31 12:11'
updated_date: '2026-08-31 12:36'
labels:
  - tooling
  - docs
dependencies: []
priority: medium
type: enhancement
ordinal: 319000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a note written to stop an auditor from misreading a table's policy list appears WHERE that auditor reads — doc/db's table page — not only inside the live catalog.

FOUND during 308's second half: the ruled documentation (COMMENT ON TABLE public.system_info explaining that the upgrade service writes its keys over a superuser connection outside RLS, so the policies govern users only) was applied and verifiable via obj_description — yet regenerating doc/db produced a NET-ZERO diff. The table pages are \d-style dumps: they render the Policies block and the per-COLUMN Description column, but no table in the whole tree shows a TABLE comment. The exact reader the 308 ruling protects (someone reading 'admin_user only' in the policy list) never sees the correction beside it.

THE FIX: teach the doc/db generator to render the table-level comment (obj_description) on each table page, near the policy block. Expect a one-line gain on every already-commented table — review that diff deliberately, it is a documentation catch-up, not noise. Then the 308 comment migration is re-created and ships (its floor-guard interaction resolved by the sibling ticket).

SIBLING: the daemon-floor guard currently treats COMMENT ON <daemon relation> as structural and demands a floor bump — a false requirement for a statement that changes nothing the daemon reads. That refinement is its own reviewed change (safety machinery): the guard should ignore comment-only statements, with a test proving a comment-only migration passes and a structural one still trips.

WHAT IS ACHIEVED: table comments become part of the reviewed offline schema reference, and honest documentation stops requiring either a false daemon requirement or a guard edit smuggled into a feature unit.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**King's ruling (2026-08-31): the sibling guard-exemption is DEAD — do not build it.** His words: teaching the floor guard about comment statements requires semantically analyzing SQL — a hack. The foreman's clean-if-conservative framing did not survive his judgment and the ruling stands: the guard stays exactly as it is. Consequence for this ticket: when doc/db learns to render table comments and a comment migration ships, it takes the honest floor bump with a note (or the question is revisited when it actually bites again). Scope reduces to the generator rendering obj_description; the guard is untouched.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-31 12:36
---
Foreman (2026-08-31): dispatched to mechanic. Fix point located: doc/db table pages are bare \\d+ dumps written by the table loop at dev.sh:2935-2944 (views at 2946-2955); \\d+ never prints the table-level comment. Scope per King's ruling: generator renders obj_description; the daemon-floor guard is untouched; the re-created 308 comment migration takes an honest floor bump.
---
<!-- COMMENTS:END -->
