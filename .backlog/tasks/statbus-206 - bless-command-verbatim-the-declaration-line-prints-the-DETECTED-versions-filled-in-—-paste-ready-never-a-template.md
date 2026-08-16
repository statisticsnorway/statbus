---
id: STATBUS-206
title: >-
  bless-command-verbatim: the declaration line prints the DETECTED versions
  filled in — paste-ready, never a template
status: In Progress
assignee: []
created_date: '2026-08-16 20:14'
updated_date: '2026-08-16 20:36'
labels:
  - release
  - operator-ux
dependencies: []
references:
  - cli/cmd/release.go
  - cli/cmd/release_gate_layer_test.go
priority: medium
ordinal: 206000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: same as STATBUS-202 directive 2 — the operator pastes the printed line and it is correct; no command assembly at the console.
> FOUND: 2026-08-16, the King's live refusal run (otherwise clean — the 202/203/205 fixes all observed working): the closing declaration line still prints the template `STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION=<version>[,...] ./sb release prerelease` although the gate has just enumerated exactly which versions are modified.

THE FIX (checkMigrationImmutability's closing block, cli/cmd/release.go): join the parsed versions of the modified files (version != 0) comma-separated and print the CONCRETE command verbatim on its own line: `STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION=20260218215337 ./sb release prerelease` (multi-file: comma-joined). Only when NO version parsed (all unparseable filenames) fall back to the template form. The surrounding declare-it framing text is unchanged.

SEQUENCING (King informed of the tradeoff): built now, commit HELD until his tag lands — landing pre-tag would move the tip and reset his CI wait; it lands immediately behind the tag unless he says otherwise.

ORACLE: extend the 205 immutability-output tests — single modified version → the exact concrete line; two versions → comma-joined; unparseable-only → template fallback.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The refusal's declaration line is the concrete paste-ready command with the detected version(s) comma-joined; template only when no version parsed
- [x] #2 The three output arms are unit-pinned alongside the 205 immutability tests
- [ ] #3 Observed verbatim on a real tripped preflight
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-16 20:16
---
Build complete (foreman-direct, same lane as 205), FROZEN for architect review. COMMIT HELD until the King's tag lands, per the ratified sequencing.

Fix (cli/cmd/release.go, checkMigrationImmutability closing block): the declaration line now collects the parsed versions of the modified files (version != 0), dedupes + sorts via dedupeInt64Sorted, comma-joins, and prints the concrete paste-ready command verbatim. Template form survives only when no version parsed. Framing text unchanged.

Oracles (release_gate_layer_test.go, +3 tests beside the 205 arms; small gitAddCommit helper factored out of the fixture):
- DeclarationLine_SingleVersionVerbatim: exact concrete line present AND no '<version>' template remnant.
- DeclarationLine_TwoVersionsCommaJoined: two released migrations both edited → '=20260101000000,20260102000000' in one line.
- DeclarationLine_TemplateFallbackWhenUnparseable: only notaversion_odd.up.sql modified → template line survives.

gofmt clean, go vet + go build green, full cmd immutability+layer test set green (includes the four 205 arms — no regression).
---

author: foreman
created: 2026-08-16 20:17
---
Architect APPROVED as frozen, no amendments (independently ran the three new arms + the 205 set: green, no regression). Commit stays HELD per the sequencing: it lands immediately behind the King's tag, or first if he sends the one-word override. Foreman is watching origin for the tag.
---

author: foreman
created: 2026-08-16 20:22
---
SEQUENCING CORRECTION (architect's call, executed immediately): the frozen diff sat in the SHARED tree — which is the King's cut tree — and his preflight clean-tree check refused on it. Mini-window executed: diff exported to tmp/206-wip.patch (157 lines, md5 d6a6a67e797b52b85dd1becf7b4abedd), both files reverted via git checkout, tree verified clean at 5d141d3ca (only the untracked backlog file remains — invisible to the tracked-only clean-tree check), git apply --check green. Restore armed on the tag watcher: on the new RC tag → apply patch, verify md5-identical, re-run tests, commit + push behind the tag. The approved-as-frozen verdict maps byte-for-byte onto the patch.
---

author: foreman
created: 2026-08-16 20:36
---
LANDED as 821aaf066, pushed; tree clean. Sequencing postmortem: the King DID cut before retiring — the tag is v2026.08.0-rc.01 at 5d141d3ca (the month rolled to August, so the version prefix changed). My tag watcher was pattern-pinned to v2026.07.0-rc.* and never fired — foreman prediction error, caught on the overnight-orders state check. Restore was byte-verified: re-applied patch diff md5 d6a6a67e797b52b85dd1becf7b4abedd identical to the architect-approved freeze; gofmt/vet/build/tests green before commit. AC#1+#2 checked; AC#3 (observed verbatim on a real tripped preflight) stays open for the next live refusal.
---
<!-- COMMENTS:END -->
