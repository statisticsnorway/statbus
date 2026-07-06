---
id: STATBUS-045
title: 'doc-db-refresh: regenerate stale doc/db/ from the current schema and commit'
status: To Do
assignee:
  - architect
created_date: '2026-06-12 21:51'
updated_date: '2026-06-30 21:58'
labels:
  - docs
  - hygiene
  - db
dependencies: []
references:
  - .claude/hooks/doc-db-freshness.sh
  - doc/db/
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the offline schema reference matches the current migrations.
> BENEFIT: every agent can grep the schema offline again — the freshness hook currently BLOCKS doc/db searches, forcing live-DB queries each session (it has already cost detours in the 039 and seed-identity sessions).
> STAGE: Hygiene.
> COMPLEXITY: mechanic-simple (regenerate + commit) with the architect blessing the diff per the security-gate convention.
> DEPENDS ON: nothing.

---

The doc/db freshness hook (.claude/hooks/doc-db-freshness.sh) BLOCKS searches of doc/db/ because committed migrations are newer than the committed doc/db dump: last migrations/ commit 785f7df57 (2026-06-04) vs last doc/db/ commit a78da3ca1 (2026-06-03). Hit during the STATBUS-039 session (had to query the live DB for chk_upgrade_state_attributes instead).

FIX (the hook's own prescription): ./dev.sh generate-doc-db (requires a running dev database) → git add doc/db/ → commit "doc: refresh db docs". Per the doc-db commit-gate convention, review the diff for security weakening/omission before blessing.

Standing hygiene — cheap, unblocks offline schema searches for every agent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 doc/db/ regenerated from the current schema and committed; the freshness hook passes
- [ ] #2 The doc/db diff reviewed against the security-gate convention before commit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
doc/db is STALE (architect noted 2026-06-30, during seed-identity verification): the doc-db-freshness hook blocks doc/db searches because migrations are newer than the last regen (migrations last commit ~2026-06-20; doc/db last commit ~2026-06-17). Had to query the live DB instead of doc/db for the seed audit-column scan. Refresh via `./dev.sh generate-doc-db` + commit.
<!-- SECTION:NOTES:END -->
