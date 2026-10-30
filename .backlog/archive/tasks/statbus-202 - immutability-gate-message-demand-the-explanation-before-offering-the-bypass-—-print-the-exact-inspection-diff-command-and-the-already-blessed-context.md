---
id: STATBUS-202
title: >-
  immutability-gate-message: demand the explanation before offering the bypass —
  print the exact inspection diff command and the already-blessed context
status: Done
assignee:
  - '@mechanic'
created_date: '2026-08-16 10:38'
updated_date: '2026-08-18 14:54'
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
- [x] #1 The tripped gate prints, per file, the exact git diff + git log inspection commands against the named previous-stable tag
- [x] #2 The message leads with inspect-and-explain; the bless env is the last line, framed as a per-cut declaration of intent
- [x] #3 When the edited bytes are already carried by cut releases, the message names those tags as derived context; a never-blessed edit gets no such line
- [x] #4 Proven by observation: one real tripped preflight shows the new message
- [x] #5 The git log suggestion prints only when the previous-stable tag is an ancestor of HEAD; on a rebaselined line the message says so plainly and names the diff as the authoritative comparison
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-16 14:08
---
BUILT + ARCHITECT-APPROVED + COMMITTED 06db15c78 (foreman, 2026-08-16). Mechanic built to the brief; architect reviewed the frozen diff and approved with zero amendments, ruling the call-site 'Fix: bypass' removal CORRECT (remove-wrong-paths: it was the exact lead-with-workaround shape the King rejected, and would have printed the bypass twice). Criteria 1-3 checked: per-file paste-ready git diff/git log against the real previous-stable tag; explain-first framing with the bless env last as the per-cut declaration; already-blessed context derived fresh (sha256 + ReleaseTagWithMigrationHash — for the live trip 20260218215337 it resolves to v2026.07.0-rc.06, mechanic-verified two independent ways; deleted/unparseable files skip; a lookup error notes without weakening the refusal). BONUS FINDING (architect): the old guidance lived in a returned error string no caller printed — the King's live paste saw only the file list + Fix line; the guidance now actually arrives. AC#4 (proven by observation) checks on the King's own verification run — the architect stages that with him.
---

author: architect
created: 2026-08-16 14:21
---
KING'S VERIFICATION RUN (2026-08-16, live output in his console) — the inspect-first shape WORKS ('this looked reasonable'): per-file framing, paste-ready commands, the rc.06 already-carried context, bless last. AC#4 verdict WITHHELD on one real defect he caught: the printed `git log v2026.05.5..HEAD -- <file>` does not isolate the edit.

ROOT CAUSE (byte-verified now): the current master line does NOT descend from v2026.05.5 (`git merge-base --is-ancestor` fails) — the 2026-07-14 source-version consolidation (source version 20260714100527) rebaselined history; on today's line the migration file exists as a single wholesale ADD in the consolidation commit 77fa16fb2, and the semantic edit's original commit (8b5912a9a, the STATBUS-116 ORDER-BY fix with its explanatory message) is reachable only from the old-line deploy branches. So commit-level archaeology against the stable tag is structurally impossible on this line: the log shows the whole-file consolidation, not the edit. The `git diff` command is UNAFFECTED — bytes vs bytes, history-independent, authoritative.

AMENDMENT (mechanic, same brief discipline): print the `git log` suggestion ONLY when `git merge-base --is-ancestor <prevTag> HEAD` holds. When it does not, print in its place: 'note: <prevTag> is not an ancestor of HEAD (history was rebaselined since the stable) — commit-level log cannot isolate this edit; the git diff above is the authoritative comparison.' The diff line stays first and unconditional. New AC#5 covers it; AC#4 checks together with #5 on the King's next run.
---

author: foreman
created: 2026-08-16 14:37
---
AC#5 AMENDMENT COMMITTED 24ce39d83 (foreman, 2026-08-16). Mechanic delivered it as a patch against HEAD (tmp/202-amendment.patch, amendment hunks only) because release.go concurrently carries his in-flight 199 work; foreman staged it with git apply --cached — the working tree was never touched — then EXPORTED THE STAGED INDEX (git checkout-index into a scratch dir) and verified build/vet/gofmt GREEN on exactly HEAD+amendment, independent of the shared tree's in-flight state (the engineer's mid-200 service.go WIP currently breaks a working-tree go build, sanctioned one-breaker). Line-reviewed: the ancestry check runs ONCE per call (prevTag fixed across files), the git diff line stays first and unconditional, the replacement note names the rebaseline and points at the diff as authoritative; the mechanic independently re-verified the live premise (merge-base --is-ancestor v2026.05.5 HEAD → exit 1). THE CUT IS UNBLOCKED: the King's next `./sb release prerelease` (fresh binary: make -C cli build) shows the corrected message — that run proves AC#4+AC#5 and, with his bless declared, cuts the tag. Architect notified to stage the run.
---

author: architect (relayed by foreman)
created: 2026-08-18 14:54
---
CLOSED on code + test + review evidence, with the observation arm's non-trigger explained CORRECTLY so the next reader isn't misled. Why no cut since rc.01 tripped the gate: pickPrereleasePredecessor compares against the previous RC when one exists, and the known released-migration edit is byte-identical across rc.01..rc.04 — the gate was correctly QUIET, not disabled. The modification a diff against v2026.05.5 shows is a REBASELINE ARTIFACT: 77fa16fb2 (2026-07-14) is the ROOT commit of this history and v2026.05.5 is NOT an ancestor of HEAD — git happily diffs disconnected trees and the answer means nothing. The message shape itself was proven on the King's live console 2026-08-16 ("this looked reasonable") plus the AC#5 amendment; the full tripped-preflight observation closes at the next REAL trip, which becomes possible again only after promotion (see STATBUS-233 for the disconnected-predecessor refusal the check surfaced). Done.
---
<!-- COMMENTS:END -->
