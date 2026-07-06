---
id: STATBUS-132
title: >-
  harness-sb-origin-preflight: fail fast locally when the sb build commit is not
  on origin
status: To Do
assignee: []
created_date: '2026-07-03 22:04'
labels:
  - install-recovery
  - testing
  - fail-fast
  - follow-up
dependencies: []
ordinal: 133000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a condition knowable locally in milliseconds must never cost a paid VM to discover.
> BENEFIT: every run launched with an unpushed HEAD (routine, since board edits create local commits) fails in milliseconds with "push first" instead of burning a Hetzner VM + ~10 minutes and dying mid-scenario with "fatal: bad object" (the r3 loss, and it will recur).
> STAGE: Testing foundation.
> COMPLEXITY: mechanic-simple (one pre-flight in the harness, matching the existing fail-fast pattern).
> DEPENDS ON: nothing.

---

DISCOVERED during the park-scenario VM runs (2026-07-04 night): run r3 burned a paid Hetzner VM and ~10 minutes to discover a condition that was knowable locally in milliseconds. Mechanism: dev.sh auto-rebuilds ./sb at run start embedding `git rev-parse HEAD`; the Backlog.md board tool creates a LOCAL commit on every ticket edit, so HEAD routinely sits ahead of origin between code pushes; the harness uploads that sb to the VM, whose clone only has origin — the freshness check's `git diff <embedded-commit>` then dies with "fatal: bad object" mid-scenario, after provisioning + bootstrap + install.

THE CHANGE: a local pre-flight in the install-recovery harness (before any VM is provisioned): resolve the commit that will be embedded in the uploaded sb (git rev-parse HEAD at build time) and verify it exists on origin (git branch -r --contains, or git fetch --dry-run probe / ls-remote + merge-base check). If not: fail immediately with the actionable message "HEAD (<sha>) is not pushed — the VM cannot resolve it; push first (board edits create local commits), then re-run."

Same fail-fast-actionable pattern as the existing pre-flights. Filed by foreman; the r3 log (tmp/vm-run-park-scenario-8641445eb-r3.log) is the reproduction record.
<!-- SECTION:DESCRIPTION:END -->
