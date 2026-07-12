---
id: STATBUS-163
title: >-
  window-off-teardown-race: the completion read-only-OFF flip dies with the pass
  connection — the window outlives completed and wedges fresh machinery writes
status: To Do
assignee: []
created_date: '2026-07-12 12:35'
updated_date: '2026-07-12 12:44'
labels:
  - upgrade
  - recovery
  - product
  - data-safety
dependencies: []
references:
  - STATBUS-110
  - STATBUS-154
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/exec.go
priority: high
ordinal: 164000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: when an upgrade reaches its terminal, the read-only window is provably lifted (or provably held, on the deliberate ABORT arm) — the flip is as teardown-immune as the terminal write itself.
> STAGE: upgrade recovery / read-only window. FOUND: 2026-07-12, the STATBUS-110 AC-2 crash-window rider's FIRST run (mid-tx arc run 29178487598, commit d07cae53b) — the architect pre-registered the OFF-probe red as a product finding before the run, and it fired.
> COMPLEXITY: architect rules the fix shape; likely engineer-small (the immune primitive already exists — 154's terminalUpdate).

OBSERVED (tmp/110-rider-run-job.log, 6283 lines):
- B's progress log at completion (line 5670): "Warning: could not clear read-only window at completion: conn closed" followed by "Upgrade to 5301df77 complete!" — the OFF flip failed on the pass connection's teardown and the completion proceeded anyway, leaving default_transaction_read_only=on system-wide with state='completed'.
- THE PREDICTED SIBLING FIRED (154 comment #3 named this class in advance): the recovery ./sb install's post-completion install-record INSERT (install.go:2403) ran on a fresh session, inherited the stuck window, and failed LOUD: "INVARIANT POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS violated ... cannot execute INSERT in a read-only transaction (SQLSTATE 25006)" — install exit 1.
- The rider's OFF probe then read SHOW default_transaction_read_only='on' after the completed terminal (line 5561) — exactly the assert built to catch this.

THE MECHANISM (same class as STATBUS-154's park-write race, different write): the window-OFF ALTER DATABASE at completion rides a connection that the completing pass is simultaneously tearing down — "conn closed" — and the failure is a WARNING, not an escalation, so completion proceeds with the window stuck on. 154 consolidated the terminal STATE writers onto the teardown-immune terminalUpdate (Background ctx + fresh daemon-tagged connection + bounded retry + session read-only-off); the window flip was not among them because it is not a state write.

IMPACT: a completed box whose window never lifts — external writes stay blocked after a successful upgrade (the exact inverse of the crash-freeze intent: freeze is for UNDECIDED windows, not terminals), and every fresh non-exempt machinery session breaks with 25006 until someone deliberately clears it. The rider caught it on first contact.

FIX DIRECTION (for the architect to rule, not pre-decided): move the terminal window flips (completion OFF, rollback OFF — and the deliberate ABORT hold stays a hold) onto the same teardown-immune primitive as the terminal writes, or an equivalent immune path; and rule whether a failed OFF flip may ever be a warning (the honest posture is likely the 154 exit invariant: a terminal that cannot flip its window escalates loudly, never completes silently wedged).

EVIDENCE: tmp/110-rider-run-job.log lines 5550-5561 (invariant violation + probe), 5670 (the warning), 5857-5859 (post-recovery row + window state). STATBUS-110 AC-2 stays open pending this fix + a green re-run; the rider is proven as an instrument either way.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect ruling recorded: the teardown-immune shape for the terminal window flips, and whether a failed flip may ever complete-with-warning (vs the 154 exit invariant)
- [ ] #2 The completion OFF flip survives its pass's teardown; the mid-tx arc's OFF probe goes green on a real box (the STATBUS-110 AC-2 oracle re-run)
- [ ] #3 A fresh machinery session after a completed terminal writes successfully (the install post-completion insert path proves it in the same run)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-12 12:44
---
RULED (architect, 2026-07-12). This is the 154 class on the window flip, and the fix is the 154 machinery applied to it — plus one invariant decision and one loud backstop.

(1) TRANSPORT: the terminal-site window flips ride terminalUpdate's teardown-immune primitive. Extract the primitive's core into a non-row-returning sibling (terminalExec: context.Background + own deadline, fresh daemon-tagged connection per attempt via recoveryDSN, session SET default_transaction_read_only = off — which is exactly what lets a fresh session execute the ALTER DATABASE mid-window — bounded retry, non-conn errors returned immediately). setDatabaseReadOnly(false) at BOTH terminal sites rides it: completion (service.go:5668) and rollback (:6899). The always-fresh connection structurally kills the observed failure ('conn closed' on the dying pass's queryConn) exactly as 154 killed it for row writes. The ON site (:4799) stays as-is: it runs mid-pass on a live conn, and ON is best-effort BY RATIFIED DESIGN (an accident-guard failing to engage degrades protection, it does not corrupt state). The ABORT terminal's deliberate read-only hold stays untouched.

(2) THE INVARIANT DECISION: a failed OFF flip at completion may NOT complete-with-warning. The 163 evidence shows why the warning was a lie: a completed box with the window stuck ON is not 'upgraded with a cosmetic wart' — it is a REGISTRY THAT REJECTS EVERY WRITE (worker, app, integrators) while reporting completed, and the very next writer died on 25006. In the NSO frame that is a broken box masquerading as healthy — the exact class 154's exit invariant exists for. Shape: the completed row write lands FIRST (unchanged — the row truth is senior), then the OFF flip via terminalExec; if the flip fails after bounded retries, escalate LOUDLY (invariant-named stderr + markTerminal-class message naming the frozen state and the remedy './sb install clears it') — never the quiet Warning line. Same at the rollback site.

(3) THE LOUD BACKSTOP: extend the existing boot-time stale-state reconciliation (cleanStaleMaintenance's surface) with a sibling: when NO upgrade is in flight (no flag, no in_progress row) and the database default is still read-only, clear it with ONE loud line naming what was found and why it is stale. This is the cleanStaleMaintenance precedent, not a silent self-heal — and it carries the recurrence-indicts property: post-fix the stale case is near-unreachable (the immune flip), so if this backstop EVER fires, the flip broke its invariant and that firing is the investigation trigger. Without the backstop, the unreachable residue is a frozen NSO registry waiting for a human who cannot SSH in — a travel event.

(4) ORACLE: the 110 AC#2 rider re-run green on the mid-tx arc — the OFF probe is the exact assert that caught this (rider proven as an instrument on its first live red). Engineer-scoped; structural pins in the style of 154's (flip sites use terminalExec, never the pass conn) + the canceled-parent/closed-conn behavioral test on terminalExec.
---
<!-- COMMENTS:END -->
