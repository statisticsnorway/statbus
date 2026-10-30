---
id: STATBUS-547
title: >-
  A ticket-only release commit carries an sb that names a different commit, so
  reinstalls on a shallow box stop with exit 69
status: In Progress
assignee: []
created_date: '2026-10-30T17:22:00Z'
updated_date: '2026-10-30T17:22:00Z'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 473204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Every commit's sb image contains a program that states that commit, so the program and the code it runs against always agree.

### Zoom out
images.yaml copies the previous commit's images onto a commit that changes only CI-exempt paths (.backlog/, doc/db/...), to save the ~20-minute build (STATBUS-219). For app, worker, db and proxy that is harmless: the code is identical and nothing inside names its commit. sb is different: its commit is baked in at build time (-X cmd.commit) and sb compares it with the checkout before any mutating command (cli/internal/freshness). A copied sb image names the parent commit. On a box with full history git can show that cli/ did not change, but an installed box has a depth-1 checkout, so the parent commit is unknown, git diff exits 128, the guard calls the binary stale, self-heal fetches the same copied image and the command stops with exit 69 (exitBinaryUnusable).

### Zoom in
- **Field case:** v2026.10.6-rc.01 was tagged on d78b2c8aa (backlog-only). Images run 41073602992 retagged sb from bd2125c3. LXD fleet run 41076193713: seven 5-install-* scenarios that rerun install.sh --commit on the installed box stopped right after 'Installed program: sb version bd2125c3' with exit 69. Prototype: a depth-1 clone of d78b2c8aa gives 'fatal: bad object bd2125c3' for the freshness diff (tmp/journal.md).
- **Owner decision 2026-10-30 (option B):** sb is always built for its own commit; the retag path copies only app, worker, db and proxy. Building sb takes about one minute (both arches, Images run 41068442946), against ~20 minutes for the full build that exempt pushes still skip. Option A (make the guard lenient) was rejected: it would hide a binary that misstates its own identity, which also shows in sb --version, the UI footer and support bundles.
- **Out of scope:** the freshness guard itself is unchanged; it is right to refuse a binary whose commit differs from the checkout.

### Closing review
- **Memory:** none. **Documentation:** the STATBUS-219 comment in images.yaml states why sb is the exception. **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 On a CI-exempt-only push, images.yaml builds and publishes statbus-sb for that commit (both arches, manifest) and retags only app, worker, db and proxy from the parent
- [ ] #2 After the change lands, a real backlog-only push to master produces statbus-sb:<that commit> whose 'sb --version' states that commit (run ID and output recorded)
- [ ] #3 The next release candidate's LXD fleet runs the seven 5-install-* scenarios that failed on rc.01 without exit 69 (run ID recorded)
- [ ] #4 A workflow test pins the split: sb is built on every push, including exempt-only pushes, and the retag matrix holds only app, worker, db and proxy
<!-- AC:END -->
