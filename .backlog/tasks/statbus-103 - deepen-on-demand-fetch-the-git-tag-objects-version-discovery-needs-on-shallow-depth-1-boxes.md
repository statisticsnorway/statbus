---
id: STATBUS-103
title: >-
  deepen-on-demand: fetch the git tag/objects version-discovery needs on shallow
  (--depth 1) boxes
status: To Do
assignee: []
created_date: '2026-06-20 10:35'
labels:
  - upgrade
  - git
  - version-discovery
dependencies: []
priority: low
ordinal: 103000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King-flagged 2026-06-20 (#3 of the channel-bless morning findings). NOW DECOUPLED from blessing (STATBUS-102 removed the bless's tag dependence) — so this is cosmetic/diagnostic only: version discovery / describe on a real box.

CONTEXT: real boxes are `git clone --depth 1` (shallow, cli/cmd/install.go:929). A shallow clone may lack a release tag's commit/tree, so version-discovery/describe (`git describe`, `git rev-parse <tag>:<path>`, latest-release lookup) can return incomplete/empty info.

THE PRINCIPLE (King): pull in exactly what's needed at the point of need, not un-shallow the whole repo. e.g. `git fetch --depth 1 origin refs/tags/<tag>` fetches that one tag's commit+tree in a cheap round-trip. NOTE: `git describe` walks history and can still fail on a truncated clone even with the tag present — so the exact fetch depends on what discovery actually asks for.

SCOPE: (1) ground WHERE version-discovery/describe depends on tags and WHAT it needs (the exact git calls + call sites). (2) implement a targeted deepen-on-demand fetch at those points. (3) verify on a shallow box that discovery returns correct info.

OWNERSHIP: operator/mechanic grounds (1) read-only -> engineer/mechanic builds (2) -> foreman gates. Low priority (cosmetic, off the bless path).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Grounded: the exact version-discovery/describe call sites + git operations that depend on tags being present, and what each needs on a shallow clone
- [ ] #2 A targeted deepen-on-demand fetch (e.g. fetch the specific needed tag at depth) added at those points — not an --unshallow of the whole repo
- [ ] #3 Verified on a shallow (--depth 1) box that version discovery/describe returns correct info
<!-- AC:END -->
