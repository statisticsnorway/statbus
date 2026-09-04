---
id: STATBUS-241
title: >-
  abort-restore-loses-backup-path: the ABORT branch's volume rewind erases the
  recorded backup_path and no terminal write re-imposes it — the abort-hold
  guard fails open by a second route
status: Done
assignee:
  - '@engineer'
created_date: '2026-08-19 00:16'
updated_date: '2026-08-28 21:37'
labels:
  - upgrade-recovery
  - release
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - '.backlog/completed/statbus-228 (comments #15+)'
priority: high
type: bug
ordinal: 234000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A box whose upgrade aborts on the git-corrupt route is supposed to keep a read-only hold on its broken volume until a human replays the retained backup — but the abort path itself erases the row's record of that backup, so the hold's guard reads zero and releases early on exactly the population it protects. This is STATBUS-228 Defect 1's fail-open reached by a second route, found by prediction during the rc.05 arc corrections, before any fleet observed it.

WHAT THE EVIDENCE SHOWS (engineer, STATBUS-228 comment #15, verified at source): the ABORT branch calls restoreDatabase (service.go:8609) BEFORE its terminal write. That restore rewinds the database volume — and with it public.upgrade — to the pre-upgrade snapshot, taken BEFORE the post-reconnect recorder ran, where backup_path is NULL. NONE of the four writeRollbackTerminal call sites re-impose backup_path (:2971, :8302, :8332, :8704 — they impose only state/error/recovery_attempts). The mechanism is proven, not theorized: it is exactly why recovery_attempts needs explicit re-imposition (STATBUS-181), demonstrated live at rc.03 where the counter stuck at 1.

CONSEQUENCE: the abort-hold guard (service.go:3841, SELECT COUNT(*) ... state='failed' AND backup_path IS NOT NULL) reads zero, and the read-only hold protecting the broken volume is stripped early. STATBUS-111's human-gated replay also cannot see the row.

PREDICTED OBSERVABLE: restore-broke-reattempt-arc.sh:480 — newly reachable after the rc.06 arc corrections — asserts a non-null backup_path on this route and is PREDICTED TO FAIL. That red, if it appears, is a PRODUCT finding confirming this ticket, never a stale assertion; the arc's failure message says so in place (escalate, don't edit).

THE FIX SHAPE (architect rules): re-impose backup_path in the terminal write after the volume rewind, the same pattern STATBUS-181 established for recovery_attempts — the flag carries the identity across the rewind, so the value exists to re-impose. Whether this lands before the rc.06 cut or the cut deliberately measures the prediction first is the architect's fork, ruled on STATBUS-228.

WHAT IS ACHIEVED: the read-only hold on a broken volume holds for as long as the replay it gates remains undone — by mechanism, on both routes that can erase the record.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect rules the fix shape and the sequencing (fix before rc.06 vs cut-and-measure the prediction)
- [x] #2 backup_path survives the ABORT-route volume rewind onto the terminal row, with a RED-first oracle at the unit level
- [ ] #3 restore-broke-reattempt phase (ii)'s :480 assertion observed GREEN at a suite run — the 228 recorder's evidence finally executes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLOSED on the tester's evidence sweep (2026-08-28): the fix landed at c140c358c, and the fleet observation arm is satisfied by the same three consecutive green fleets (rc.14/15/16) exercising the abort/rollback paths — including rc.16's 36/37 run where every rollback-family scenario passed.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (pinned by foreman)
created: 2026-08-19 00:17
---
RULED (architect): FIX TONIGHT — and the fork DISSOLVES, because the measurement rides the same run. Cut-to-measure is right when the premise rests on something uninspectable; this is the opposite — arithmetic on readable code (:8609 restore before terminal write; four terminal call sites, none imposing backup_path; the rewind documented in our own :7979-7985 comment; the identical mechanism OBSERVED live at rc.03 on recovery_attempts). Deliberately cutting a candidate to confirm arithmetic is ceremony, not evidence. And what would ship meanwhile is a safety hold failing OPEN on a broken volume — indefensible on the promotion candidate. THE FIX'S SHAPE, the whole review point: re-impose backup_path FROM THE FLAG, never from a remembered variable — the flag is the authoritative carrier across exactly this gap (228 ruling), and 229 made its value correct on BOTH routes by construction (empty on PreSwap, identity post-swap), so flag-sourcing writes the right value on either arm where a remembered variable could resurrect an identity on a route that must not carry one. MEASUREMENT CONDITION: rc.06's suite ASSERTS the non-null column at :480 (already true in the landed arcs) — the fix proves itself in the run that would have demonstrated the defect. ON THE RECORD, the architect's own miss: he cited :7979-7985 himself in the 228 review and did not apply the mechanism one column over; the builder verified the prediction instead of inheriting it — third builder-upward correction of the day, arriving BEFORE the cut because of it. Morning ticket (separate): the terminal-write path needs a GENERAL answer — every restore-rewound column the terminal must preserve, enumerated once — not a third one-column patch.
---

author: engineer
created: 2026-08-19 00:26
---
**BUILT to ruling #1. FROZEN, no commit.** Three files: `cli/internal/upgrade/service.go`, new `cli/internal/upgrade/terminal_backup_path_reimpose_test.go`, and an AMENDED landed pin in `backup_path_carriers_test.go` (flagged below — review that specifically). AC#2's code + oracle are here; AC#3 rides the cut.

**THE FIX — flag-sourced, in the shared write, on all FIVE call sites.** `writeRollbackTerminal` resolves the identity itself via a new `flagSourcedBackupPath()` and passes it as `$4`; every terminal UPDATE carries a named constant `terminalBackupPathSQL`. The value is read INSIDE the helper, so there is no parameter a caller could supply — the review point is enforced by the signature, not by a comment.

**FIVE, not four.** The ticket names :2971/:8302/:8332/:8704; the tree has a fifth, `LabelFailedAbortServicesLive` (the STATBUS-187 services-not-stopped ABORT). Same class, same rewind exposure — it would have been the one path left silently erasing the column. All five carry the clause, and the pin counts terminal UPDATEs against `writeRollbackTerminal` call sites so a sixth cannot appear unnoticed.

**THREE STATES, DELIBERATELY DISTINCT — answering “silence and empty must not be conflated” explicitly.** `backup_path = CASE WHEN $4::text IS NULL THEN backup_path ELSE NULLIF($4::text, '') END`:
- **flag readable, path set** → impose the identity (the ABORT route: this is the fix).
- **flag readable, path empty** → impose SQL NULL *explicitly*, not skip. PreSwap's “nothing moved ⇒ no identity” becomes something the terminal write ENFORCES, so a rewind cannot resurrect one onto a route that must not carry it — the contract the rc.06 arcs now assert.
- **flag NOT readable** → leave the column untouched, log loudly. **Required, not defensive:** STATBUS-111's replay reaches `restoreAndFinalize` with NO flag (the restore-broke terminal removed it). Imposing NULL there would erase a live identity `reconcileBackupDir` needs — the naive “empty when unknown” shape would have introduced a NEW erasure while fixing this one.

**ORACLES — all three RED-VERIFIED against mutations:**
1. **Source pin** — stripped the clause from ONE call site (the ABORT branch, the exact defect): FAILS, printing the offending SQL line verbatim.
2. **Three-state behavioural** — collapsed “unknown” into “empty”: FAILS naming the flagless replay path. Runs against real flag files, both read paths (held descriptor, on-disk fallback).
3. **Flag-sourcing** — changed the helper to take a `backupPath *string`. I made the mutation actually COMPILE (updating all five call sites) rather than accepting a build break as the red, since a build break proves nothing about the assertion. Both arms fire: missing `flagSourcedBackupPath()` AND the forbidden parameter.

**A ZERO-SCOPE DEFECT IN MY OWN PIN, caught by mutation and fixed.** The signature check first read from the function start to the first `)` — which closes the RECEIVER `(d *Service)`, capturing no parameters at all. It passed against everything, including the mutation it exists to catch. It now starts after the parameter list's opening paren AND asserts the extraction contains the known `attempts int` parameter, so a future extraction bug fails loudly instead of examining nothing. Found only because I mutated and watched for green.

**AMENDED LANDED PIN — `TestFlagInvariant_EveryPhaseAndBackupPathWriterIsAccountedFor_STATBUS232` (mine, from 232).** It failed on my new code, reporting `if flagBackupPath == nil {` as an unaccounted WRITER. False positive: the matcher tests `Contains(trimmed, "BackupPath =")`, which also matches `BackupPath ==` — contradicting the sentence directly above it (“not reads, not comparisons”). **I did NOT add my reader to `known`**: that would have silenced a true report of a broken matcher, left every future comparison mis-classified, and taught the next person to silence the pin rather than answer it. I fixed the matcher to exclude `==`/`!=`. Verified BOTH ways: clean tree passes, and an injected real assignment (`sneak.BackupPath = "/resurrected"`) is still caught — repaired, not relaxed.

**VERIFY CHAIN (from `cli/`):** `go build ./...` OK. `go test -count=1 ./...` — **12 packages ok, 0 failures**. `gofmt -l` clean on all three of my files (other names it lists are pre-existing drift I did not touch). `golangci-lint run ./...` — **0 issues**, and I probed that it actually analysed rather than trusting the number: an injected `declared and not used` was caught, so this is not the doc-033 lint false-green.

**COMMIT MESSAGE MUST CARRY:** the fleet proof RIDES the cut — rc.06's `restore-broke-reattempt` phase (ii) `:480` asserts the non-null column, so the run that would have demonstrated the defect is the run that proves the fix. Nothing here is proven by the landing.
---

author: architect (pinned by foreman)
created: 2026-08-19 00:28
---
APPROVED AND LANDED as c140c358c. Verdict highlights (architect): (Point 3) the FIFTH call site is real — :8664 LabelFailedAbortServicesLive — and "four" was inherited from the ticket: "I verified the mechanism instead of the enumeration... twice in one night I checked the hard part and accepted the list. An enumeration handed to you is a premise, not a fact." The pin counting UPDATEs against call sites closes the CLASS, not the instance. (Point 2) the load-bearing claim verified at source: restoreAndFinalize takes backupPath as a PARAMETER supplied from the ROW after the terminal removed the flag — naive empty-when-unknown would erase the very column the 111 replay keys on; the third arm is required, the difference between a fix and a trade. The three-state design named as today's doctrine in a new form: A WRITER THAT CANNOT DETERMINE THE VALUE MUST NOT ASSERT ONE — the same rule that appeared today about checks and measurements, now about writes. (Point 1) the pin amendment is REPAIRED not relaxed — fixing the matcher preserves the invariant; adding the reader to the known-writers list would have set the mechanism dying by a thousand exemptions. Craft recorded: the flag-sourcing mutation made to COMPILE across all five sites (a build break is not a failing assertion), and the zero-scope bug in his own new pin found by mutating and watching for green. The structural ruling held in the code's shape, not the reviewer's memory. AC#3 (the :480 assertion green at a suite) rides the rc.06 cut.
---

author: foreman
created: 2026-08-19 06:59
---
v2026.08.0-rc.06 CUT at 4f3a08c00 (King's act, 2026-08-19 morning), orchestrator run 32225686284 in progress. AC#3 rides this suite: restore-broke-reattempt phase (ii)'s :480 assertion executes for the first time against the landed fix — the run that would have demonstrated the defect is the run that proves the fix. Also riding: 228 AC#3 (both corrected rollback arcs), and on FULL GREEN the observation sweep + the canary deploys (dev in parallel now, Norway after green) + the stable promotion.
---
<!-- COMMENTS:END -->
