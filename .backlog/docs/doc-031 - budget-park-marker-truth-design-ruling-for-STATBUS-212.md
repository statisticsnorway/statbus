---
id: doc-031
title: 'budget-park-marker-truth: design ruling for STATBUS-212'
type: specification
created_date: '2026-08-18 09:49'
tags:
  - upgrade-recovery
  - park
  - architecture
---
# budget-park-marker-truth — design ruling (STATBUS-212)

Architect ruling, 2026-08-18. Every premise below re-verified against the working tree at writing time, with file:line. One of the ticket's own premises did not survive that check — see Finding 2.

## WHAT THIS PART DOES

When an upgrade cannot proceed, the service **parks** the row: the box stays alive and idle rather than crash-looping, and an operator later un-parks it for one fresh attempt. Two things must be true of a parked box.

It must be **operable** — STATBUS-200/204 route every park site through `parkServiceRecovery` (service.go:5836), which era-guards the box and, if the DB is provably still at the source schema, restores the source version's services so the web UI is up while the row sits parked.

Its **marker must be truthful** — STATBUS-210 added truth-restoration at that same writer (service.go:5882): a successful restoration has returned the box to its *pre-swap* reality, so the flag's post-swap phase marker now lies about the box. Left lying, a later crash-recovery classifier reads binary(source) ≠ row-target, concludes "cannot reach new", and rolls back the very row an operator just un-parked. The rewrite is performed by `mutateHeldFlag` (service.go:598), which writes in place through the already-open file handle held under the flock.

## WHAT GOES WRONG

`mutateHeldFlag` refuses unless the service currently holds the flag file: `if d.flagLock == nil || d.flagLock.file == nil { return fmt.Errorf("no flag file held") }` (service.go:599-601). On the deterministic park path the flock is held throughout, so the rewrite lands — that is the coverage the arcs proved. At the two **budget**-park sites it is not held, `mutateHeldFlag` returns "no flag file held", a Warning prints, and the marker stays lying. A budget-parked, source-restored box that is later un-parked then hits exactly the collision STATBUS-210 was written to kill.

## THE DETAIL

**Finding 1 — the helper's contract depends on ambient caller state it neither owns nor checks.** `parkServiceRecovery` promises truth-restoration, but can only deliver it when its caller happens to be holding the flock. Nothing in the helper states that requirement, nothing enforces it, and a future park site added by someone who has not read this ticket inherits the silent half-failure. This is the same drift class the STATBUS-196 gate exists to hunt, and the same one already ruled on for this very function: STATBUS-204 comment #2 ruled the watchdog cover belongs *inside* `parkServiceRecovery` because "the chokepoint owns its invariant — a helper that does slow work owns its own liveness cover; every-caller-remembers-a-wrapper is precisely the drift class". The flag hold is the identical situation one layer over.

**Finding 2 — the ticket's premise holds for one site and not the other, so a single "reorder" ruling would silently fix half the bug.** The filing says both budget sites "release the flock BEFORE parkServiceRecovery". Verified:

- **Site 1, `RecoveryBudgetGuard`** — matches the filing. It acquires the flock (service.go:6835), parks, then calls its `release()` closure, and only afterwards opens the progress log and calls the helper (service.go:6920). A reorder would work here.
- **Site 2, `resumeNewSb` same-step-twice** — does **not** match. `resumeNewSb` (service.go:7062) touches the flock exactly once in its whole body, at roughly service.go:7434 — *after* the park branch has already called the helper (service.go:7380) and returned. On that branch the flock was never acquired at all. There is nothing to reorder, because nothing was released.

So candidate (b) from the ticket is not a fix; it is a fix for site 1 plus an untouched site 2.

**Finding 3 — the acquisition is not free-standing, and a naive one would clobber the flag.** `acquireFlock(projDir, flag)` truncates the file and writes the flag value it is handed (service.go:477-487). Acquiring therefore requires already knowing the current on-disk content. The house idiom is read-then-acquire-verbatim, which site 1 already performs (`base := *flag`, then `acquireFlock(d.projDir, base)`, with the comment "Re-write the flag content verbatim").

**Finding 4 — nothing inside the helper's span touches the flock**, so self-acquisition cannot deadlock. Verified across `parkServiceRecovery`, `parkEraVerdict` and `restoreSourceServices`: no `acquireFlock`, no `flagLock` reference in any of them.

## THE FIX

**Ruled: (d) — `parkServiceRecovery` becomes self-sufficient for the flag hold.** Not the ticket's (a), (b) or (c). Same shape as the STATBUS-204 ruling on the same function: the chokepoint owns its invariant.

At the top of the helper, adopt-or-acquire, and release only what was acquired:

- **Already held** (`d.flagLock != nil && d.flagLock.file != nil` — the same predicate `mutateHeldFlag` uses, not a new one): use it, do not acquire, do not release. The deterministic path is byte-for-byte unchanged, so STATBUS-210's arc-proven coverage is untouched.
- **Not held**: read the current flag, acquire verbatim, and `defer` the release of exactly that lock. Both budget sites then reach the rewrite with no change at either call site — and so does every future park site.

Extract the read-then-acquire-verbatim idiom into one named function rather than copying it a third time. Naming it is the point: an acquisition that must not change the flag's meaning should say so at the call site, and the failure arm then lives in one place.

**The failure arm (AC#1 requires it named): a contended flock REFUSES the whole helper — narrate and return, before any service is started.** Not "restore anyway and skip the rewrite". A live holder is, by this codebase's own doctrine, the liveness signal that another actor owns box mutations (service.go:461-463, STATBUS-111); starting source services underneath an actor that may be mid-upgrade is precisely the mixed-era guess `parkEraVerdict` refuses on every other anomaly — "EVERY anomaly REFUSES with a named narrative: the fail-safe direction is ALWAYS dark-behind-the-maintenance-page, never a guess toward serving mixed-era" (service.go:5888-5891). A contended flock is an anomaly; it takes the established exit. In practice it is near-unreachable — the only realistic contender is `./sb install` doing crash recovery, which quiesces this unit SIGKILL-class before it could hold the lock — but the arm must be correct, not merely rare.

**Fold in STATBUS-204's open nit, because this is the "next touch" it was deferred to.** Site 1 currently attempts the restoration only if the progress log opens: `if relPath := d.loadLogRelPath(...); relPath != "" { if plog := AppendProgressLog(...); plog != nil { ... } }` (service.go:6918-6923). A missing or unopenable log therefore skips the restoration entirely — the box stays dark for a bookkeeping failure. Degrade to a discard writer instead, so the narrative is lost but the box is not. Without this, "every park site produces an operable box and a truthful marker" is still false at site 1 for a second, unrelated reason, and the ticket would close on a half-truth.

**Oracles.** Extend the STATBUS-210 unit set: a budget park plus a successful restoration leaves `Phase == PhaseOldSbUpgrading` on disk, asserted for **both** sites — site 2 is the one that proves the ruling did more than reorder site 1. Add a source-parsing pin, in the family that already guards this function, that the adopt-or-acquire block precedes the era verdict, so a future refactor cannot silently drop it the way the cover pin protects the watchdog ticker. Pin the contention arm's refusal too: no service start when the flock cannot be taken. The un-park-after-budget-park story gets a structural unit; the VM-level proof rides whichever suite exercises budget parks.

## WHY THAT HELPS

The marker's promise becomes unconditional. Today "the marker always describes the box" is true on the path the arcs happen to exercise and false on two rarer paths, which is the worst shape for a safety invariant: it tests green and lies in the cases that only appear when something has already gone wrong three times. After this change the guarantee belongs to the writer that makes the claim, so it holds for the two budget sites, for the deterministic path unchanged, and for every park site anyone adds later without reading this document — which is the only version of the guarantee that survives contact with a growing codebase.
