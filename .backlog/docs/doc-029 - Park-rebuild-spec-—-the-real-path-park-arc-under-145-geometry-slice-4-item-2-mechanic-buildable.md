---
id: doc-029
title: >-
  Park-rebuild spec — the real-path park arc under 145 geometry (slice 4 item 2,
  mechanic-buildable)
type: specification
created_date: '2026-07-08 14:58'
updated_date: '2026-07-08 15:06'
tags:
  - upgrade
  - recovery
  - park
  - install-recovery
  - STATBUS-145
  - STATBUS-044
  - arc-spec
---
# Park-rebuild spec — the real-path park arc under 145 geometry

**For the mechanic** (slice 4 item 2, STATBUS-145). Written against the as-committed geometry (cb356663d). The r19-green fabricated park scenario (3-postswap-resume-died-parked) STAYS as the regression net until this arc is green — never delete proof coverage before its replacement is proven.

> **REV 2 (2026-07-08, architect — C-construction corrected after the mechanic's map-before-build trace).** Rev 1's construct sketch ("C = B with the app change reverted") was written for an app-code break; the mechanic's superior break mechanism (a MIGRATION that breaks `auth_status()`) made that sketch an ILLEGAL edit: V2 SUCCEEDED on the box, so an in-place semantic edit to it is exactly what the migration-immutability doctrine forbids — the release-channel content-hash handler (migrate.go:1662-1685) would BLESS (re-stamp, never re-run) and the function would stay broken forever, wedging step 5 for an unrelated-looking reason. The doctrine caught the spec's bug. **Corrected construction below: the fix is V3, a NEW migration.** This is also the more faithful Albania shape — real fixes ship as new migrations, not edited history.

## The finding that shapes this spec (read first)

My own slice-4 plan guessed the rebuild would drive "repeated daemon kills at the health-check step → same-step-twice → park". **That guess is WRONG under the committed geometry — traced and corrected here:**

- Deaths at PRE-delta steps (3.1-3.5) no longer accumulate: pass 2's Resuming-arm observed-state read finds the delta pending → positively Behind → **rollback wins at pass 2** (the atomicity flip). No park.
- Deaths at POST-delta steps (3.6-3.7) with an otherwise-healthy box: pass 2's self-heal canary finds containers at target + no pending + health OK → **completed**. No park.
- Deaths at post-delta steps with an UNHEALTHY box: the canary defers to the continuation, which reaches the health check and **B-parks on FIRST occurrence** (health-past-warmup, 046 slice 3a) — before a second kill can ever produce same-step-twice.

**Consequence, significant enough for doc-021 and the 071 map:** under 145 the forward D-class park (same-step-twice / death budget at the guard) has NO on-cue real-path construction left — every route either rolls back first or self-heals first. That is the product working as ratified, not a coverage hole: the guard park remains SECOND-LINE (unit-tested, r19-proven historically, still catching e.g. floor-migrate deaths and races the trace can't foresee). The LIVE park class that survives — and the one an Albania box will actually hit — is the **B-class at-target park: the delta applied, the new version cannot serve past warmup → park on first occurrence**. That is what this arc proves, together with the full park substrate (skip/siren/un-park) and the fix-release ending.

## Arc: `postswap-health-park-arc` (real path end-to-end, zero fabrication; upgrade-target.sh name: `healthpark`)

**Construct** (the 118 constructor, real branches + CI images — Rev 2, mechanic-trace-verified):
- **B = A + V1 + V2.** V1 = V_marker (benign real migration, fixture-table pattern — the delta is real and assertable). V2 = the deterministic health break: `CREATE OR REPLACE FUNCTION public.auth_status(...)` to `RAISE` — the upgrade health leg probes `/rpc/auth_status` via healthURL after `waitForRestReady`'s /ready warmup, and /ready stays green (PostgREST schema-cache load doesn't execute function bodies), so the failure lands exactly "past warmup". V2 SUCCEEDS as a migration (creating a broken function is a successful DDL) — which is what makes the box genuinely AT-TARGET when the park fires.
- **C = B + V3** (a NEW, higher-version migration that `CREATE OR REPLACE`s `auth_status()` back to the original body). **V1/V2 stay byte-identical between B and C** — immutable, as the doctrine demands; V3 rides the normal pending path on C's upgrade (C's delta onto a parked-at-B box is exactly {V3}), no content-hash machinery involved. NEVER fix by editing V2 in place — the bless handler re-stamps without re-running (see Rev 2 note).
- **Down-migrations for V1/V2/V3:** the oom/ceiling unused-down precedent applies — syntactically valid, minimal, never invoked by the arc; do not invest in semantic reversibility for synthetic test migrations.

**Run:**
1. Install A + demo data + counts snapshot. Real `register` + `schedule` B → daemon claims → executeUpgrade → exit-42 handoff (all real, claim gate satisfied by real images).
2. Boot pass: floor-migrate no-op → resume → applyPostSwap applies the DELTA at 3.5 — V1+V2 commit (**midpoint anti-vacuity assert: both recorded in db.migration + fixture present — proves the box is genuinely at-target when the park fires**) → step 11 starts services → health leg: /ready warmup passes, `/rpc/auth_status` fails past warmup → **parkForDeterministicFailure → PARK on FIRST occurrence, at-target**.
3. **Assert the park substrate** (the r19 spec, carried over): row `in_progress` + `recovery_parked_at` set + reason matching the health-past-warmup message (names the version + can't-serve); siren EXACTLY ONCE (`STATBUS_EVENT=parked` via .env.config-configured callback); unit alive-idle — NRestarts bounded AND frozen across a settle window; TWO extra deliberate service restarts → each logs the RESUME-path parked-skip line (resumePostSwap :6242 — under 145 the boot floor-migrate is a no-op, so the guard's boot-migrate skip line is NOT the marker; mechanic-trace-verified), `recovery_attempts` unchanged, NO re-siren; flag still on disk; **never `rolled_back`** at any point (at-target park must not restore — F1). Park detection: poll `recovery_parked_at` (parked rows stay `in_progress` — arc_to helpers don't apply).
4. **Un-park arm 1 (install):** `./sb install` → UN-PARKED line → ONE fresh attempt with reset budget → B is still broken (auth_status still RAISEs) → health fails past warmup again → **RE-PARK with a fresh reason and a SECOND siren** (the fires-once-per-park-EVENT contract, finally exercised live).
5. **The fix-release ending (dual oracle — this leg is DISCOVERY):** `register` + `schedule` C while B's row sits parked with its flag on disk. This is the REAL Albania recovery flow — a fix release arriving at a parked box — and the parked-B-row × new-C-upgrade interaction (flag on disk, flock free, writeUpgradeFlag's acquire against it; the parked row's supersession) is **statically underdetermined: the run is the oracle**. Expected terminal: C's delta {V3} restores auth_status at 3.5 → health passes → C completes, box serves at C, demo data intact, B's row terminal (superseded or otherwise coherently closed), no orphan flag. ANY wedge here is a product finding of the highest value, not an arc failure — report it, don't route around it.

**Anti-assertions (unchanged from r19 discipline):** no exact NRestarts pin (bound it), no timestamp/ordering pins beyond named markers, transport errors are never state verdicts; `assert_health_passes` (which hits the /rest/ root, not /rpc/auth_status) remains usable for the A-baseline and C-terminal legs.

## What this arc retires and what it does not

- ON GREEN: the fabricated park scenario's park-substrate coverage is superseded → the scenario is deleted and `fabricate_resume_state` drops to its ONE sanctioned caller (rune-wedge), completing the King's carve-out ruling (doc-028 / 071).
- NOT covered here (deliberate): the guard's D-class park arithmetic — that lives in the Go unit tests (resumeEscalation suite) + the r19 historical proof; its real-path window is closed by the atomicity flip as designed. doc-021 and the 071 map cell must say this in the same commit as the arc (park row: "live class = B at-target; D-class = second-line, unit-covered").
- The NOTIFY/apply un-park arm remains unexercised by this arc except via the C-schedule leg's adjacent machinery; keep the r3 residual note as-is.

## Dispatch-list impact

The slice-4 list gains no new runs beyond replacing "park rebuild" with THIS arc; but note step 5's discovery status — budget one extra VM round for the parked-B × schedule-C interaction if it surfaces a finding.
