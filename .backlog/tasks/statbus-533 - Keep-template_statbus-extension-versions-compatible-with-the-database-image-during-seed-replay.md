---
id: STATBUS-533
title: >-
  Keep template_statbus extension versions compatible with the database image
  during seed replay
status: In Progress
assignee: []
created_date: '2026-10-27T20:48:00Z'
updated_date: '2026-10-27T22:02:00Z'
labels:
  - database
  - seed
  - migrations
  - sql-saga
dependencies: []
priority: high
type: bug
ordinal: 459204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Extension upgrades happen in their own lifecycle step, before normal migrations. Normal migrations contain schema changes only. No migration ever tries to run an old extension update against a newer native library.

### Zoom out
The owner approved removing the old extension-update migrations and their IDs rather than building a compatibility registry. `db.migration` is for ordinary schema migrations. `db.extension_upgrade` is only an audit receipt for the direct extension upgrade event, with `extension`, `from_version`, `to_version` and `applied_at`. There is no `satisfied_migrations` list, no registry of retired IDs, no at-head exemption and no special redo behavior.

### Zoom in
- Before pending migrations are computed, the runner handles each tracked extension on the actual target DB: absent means create at the image default; older means go directly to the image default using upstream's update script and integrity check; newer means refuse, never downgrade. Fresh installs, old template replays, partial old-dump restores and production upgrades all use this same step.
- Pure extension-update migrations are removed entirely. If a migration does extension upgrading AND other work, only the extension-upgrade part is removed; every other schema change in that file stays and runs normally. The split is by responsibility, not by file.
- `db.migration` and any existing rows for pure extension-update migrations are removed along with the files. There is no compatibility registry and no fake history for those IDs.
- Future extension bumps update the image pin and use this lifecycle step, not a new migration file.

### Closing review
- **Memory:** the owner-approved split is in this ticket and the runner comments.
- **Documentation:** the migration procedure says where extension upgrades happen and why normal migrations never contain them.
- **Cleanup:** no `satisfied_migrations`, retired-ID registry, at-head exemption or special redo path remains.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 [Owner] Approved removal of old extension-update migrations and a separate extension lifecycle step before normal migrations, recorded in Implementation Notes
- [ ] #2 Before pending migrations are computed, the actual target DB creates an absent extension at image default, directly updates an older one with integrity check, and refuses a newer one without downgrading; old-template replay, partial old-dump restore and production upgrade all pass
- [ ] #3 Pure extension-update migrations and their db.migration rows are removed. Mixed migrations lose only their extension-upgrade part and keep every other schema change. No registry, satisfied_migrations, at-head exemption or special redo path exists
- [ ] #4 db.extension_upgrade records only extension, from_version, to_version and applied_at. The full fast suite and CI including the database image build are green at the fix commit
<!-- AC:END -->
