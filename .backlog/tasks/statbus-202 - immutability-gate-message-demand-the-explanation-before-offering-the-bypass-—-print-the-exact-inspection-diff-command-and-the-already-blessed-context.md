---
id: STATBUS-202
title: >-
  immutability-gate-message: demand the explanation before offering the bypass —
  print the exact inspection diff command and the already-blessed context
status: To Do
assignee: []
created_date: '2026-08-16 10:38'
labels:
  - release
  - operator-ux
  - quality-gate
dependencies: []
references:
  - cli/cmd/release.go
  - >-
    .backlog/tasks/statbus-166 -
    restamp-conveyance-a-retroactively-edited-released-migration-re-stamps-the-production-ledger-via-a-declared-old→new-hash-conveyance-—-the-exit-21-remedy-the-upgrade-path-lacks.md
priority: medium
ordinal: 202000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a tripped immutability gate makes the operator UNDERSTAND before deciding — the message leads with "explain this diff", never with the workaround.
> FOUND: 2026-08-16, the King cutting by hand: the current failure text leads with the bypass env ("Fix: ... set STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION=... to bypass") and gives no way to SEE the change being judged.

THREE IMPROVEMENTS (King-directed, first two verbatim from his console):
1. REFRAME: explanation before remedy. Per modified file, the message says: "A released migration differs from its bytes at <previous-stable>. Inspect and explain the change before deciding:" — the bypass env moves to the LAST line and is framed as the deliberate bless declaration it is (each cut re-declares intent; no stored second record — the King's bless design), not as a workaround.
2. PRINT THE EXACT INSPECTION COMMAND, per file: `git diff <previous-stable-tag> HEAD -- <migration-path>` and `git log <previous-stable-tag>..HEAD -- <migration-path>` — the operator pastes, reads, decides. No command-assembly at the console.
3. CONTEXT FROM THE RECORD (no stored intent — derived fresh, consistent with the no-second-records design): reuse the STATBUS-166 recognition machinery (bytes-carried-by-a-cut-release check) to add, when true: "these exact bytes are already carried by <tags> — prior cuts declared this bless; re-declare to proceed." A first-ever edit gets no such line and reads as the serious event it is.

GROUNDING: gate shipped 14b88c412 (2026-04-17), lives in the RC + stable preflight (cli/cmd/release.go family); the live trip is 20260218215337 (the STATBUS-116 ORDER-BY determinism fix, 8b5912a9a), blessed at every RC cut since v2026.07.0-rc.01 (STATBUS-166 AC#3). Mechanic-size once the reuse point for the 166 recognition call is confirmed; post-cut sequencing like all tracked-file work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The tripped gate prints, per file, the exact git diff + git log inspection commands against the named previous-stable tag
- [ ] #2 The message leads with inspect-and-explain; the bless env is the last line, framed as a per-cut declaration of intent
- [ ] #3 When the edited bytes are already carried by cut releases, the message names those tags as derived context; a never-blessed edit gets no such line
- [ ] #4 Proven by observation: one real tripped preflight shows the new message
<!-- AC:END -->
