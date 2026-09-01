---
id: STATBUS-132
title: >-
  harness-sb-origin-preflight: fail fast locally when the sb build commit is not
  on origin
status: Done
assignee: []
created_date: '2026-07-03 22:04'
updated_date: '2026-07-08 21:39'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NORTH STAR: a local harness run must never burn a VM on a commit origin cannot serve. SHIPPED babb2fe2e + 23065aee3 (2026-07-08), dual-reviewed (architect ship with one tightening — the fast path filters to origin/ so a fork remote cannot false-pass; foreman applied it and the SC2143 style fix). The preflight runs before any VM is provisioned: fast path checks origin tracking refs, slow path asks origin directly with prompting disabled. Refusal fires only on positive evidence (origin reachable, HEAD absent), exit 3, with a message that names the cure — including the just-pushed-but-stale-refs case, whose remedy line heals the one theoretical false refusal. All uncertain paths warn and proceed: the check saves money, never wrongly blocks. Verified three ways without touching the shared tree; caught a genuinely unpushed HEAD live during its own verification.
<!-- SECTION:FINAL_SUMMARY:END -->
