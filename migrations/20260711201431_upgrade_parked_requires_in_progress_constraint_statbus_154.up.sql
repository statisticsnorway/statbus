-- Migration 20260711201431: upgrade parked requires in progress constraint statbus 154
BEGIN;

-- STATBUS-154 — CLASS-LEVEL IMPOSSIBILITY for the parked-completed corruption.
-- A PARK marker (recovery_parked_at) is only meaningful while the row is
-- state='in_progress' (a parked row STAYS in_progress — forward-only). The
-- convicted writer, markCurrentVersionCompleted, completed a still-parked row
-- on a parked-skip boot: it left recovery_parked_at set on a 'completed' row,
-- an impossible pairing the app then mis-read ("post-unpark row: completed").
-- The Go guard closes that write; this constraint makes the corrupt pair
-- unrepresentable at the DB layer for EVERY writer (Go, the supersede
-- procedure, step-table psql) — not just the one path we convicted.
--
-- One-time legacy cleanup FIRST: any pre-existing row that already violates the
-- invariant (a park marker on a non-in_progress row) carries a STALE marker —
-- state is authoritative, so the marker is garbage. Clear it once here. A
-- migration runs once; this is NOT a standing self-heal — deliberate un-park
-- stays RunSchedule / UnparkByID only (house no-standing-self-heal rule).
UPDATE public.upgrade
   SET recovery_parked_at = NULL,
       recovery_parked_reason = NULL
 WHERE recovery_parked_at IS NOT NULL
   AND state <> 'in_progress';

-- The invariant. Both deliberate un-park paths already satisfy it:
-- recoveryBudgetResetCols (RunSchedule's atomic reschedule + UnparkByID) clears
-- recovery_parked_at in the SAME UPDATE that moves the row out of in_progress.
ALTER TABLE public.upgrade
  ADD CONSTRAINT chk_upgrade_parked_requires_in_progress
  CHECK (recovery_parked_at IS NULL OR state = 'in_progress');

END;
