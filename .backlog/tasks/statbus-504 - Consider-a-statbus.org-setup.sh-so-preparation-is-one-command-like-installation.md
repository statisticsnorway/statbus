---
id: STATBUS-504
title: >-
  Consider a statbus.org/setup.sh so preparation is one command like
  installation
status: Done
assignee: []
created_date: '2026-10-13 15:38'
updated_date: '2026-10-13 15:39'
labels:
  - docs
  - install
  - cloud
dependencies: []
priority: low
type: task
ordinal: 430204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
IDEA from the owner, 2026-10-13: with the right Ubuntu box the whole thing is one hardening command and one install command, and it could be shortened further by serving the prepare script from statbus.org the way install.sh is served. NOT to be acted on yet - the owner said not to press on it; this ticket exists so the idea is not lost.

WHAT WE KNOW: every reference in this repository, including the front page and the docs, uses `curl -fsSL https://statbus.org/install.sh | bash`, but nothing in this repository serves it: there is no Pages workflow, no Caddy route for statbus.org in caddy/templates/, and no doc saying where it is hosted. So statbus.org is served from outside this repo, and the matching rule for a second path would go wherever that is.

THE CONSTRAINT THAT MAKES THIS NON-TRIVIAL: a plain redirect of setup.sh must NOT point at the master branch, because that is exactly STATBUS-488 (the box would be prepared by unreviewed code that can drift from the release installed on it). The right shape mirrors how install.sh behaves: the path serves a small script that resolves the release the operator is installing (latest stable by default) and then fetches ops/setup-ubuntu-lts.sh FROM THAT TAG. A static redirect can only do that if the target URL itself expresses latest-stable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The decision is recorded: either add statbus.org/setup.sh, or keep the two-line prepare instruction as it now stands on the front page. Checked by this ticket carrying the chosen route and why.
- [ ] #2 If the path is added, fetching it never prepares a box from master: it resolves the release the operator is installing, exactly as install.sh does, and that is demonstrated in the ticket with the URL it produces.
- [ ] #3 The front page and doc/setup-ubuntu-lts.md are updated to the chosen form, so the repository has exactly one prepare instruction.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filed 2026-10-13 by the coordinator, deliberately left To Do. Blocked on an answer only the owner has: where statbus.org is served from, since nothing in this repository routes it.

FOLDED INTO STATBUS-505 on 2026-10-13 (owner: do not create administration for small things). The one-command prepare and the bootstrap source are a single decision, so it is tracked once, in 505. This ticket is closed as folded.
<!-- SECTION:NOTES:END -->
