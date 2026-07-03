-- Migration 20260703210000: add recovery park-degraded columns to upgrade statbus_046
BEGIN;

-- STATBUS-046 (doc-021, King ruling D3) — PARK-DEGRADED substrate for the
-- at-target forward recovery path. The rune box restarted 10,229 times because
-- systemd StartLimit cannot bound a ~160s/cycle crash loop; the real bound must
-- be an UPGRADE-ATTEMPT budget owned by recovery. These queryable columns carry
-- the park state on the row (no enum churn; admin UI / install / queries read
-- them). The crash-survivable per-attempt state (dying step) rides the on-disk
-- flag; the ROW mirror below serves everything that isn't the resuming process.
--
--   recovery_attempts       — crash-resume counter, incremented at attempt START
--                             so a dead process self-counts (D3: PROCESS DEATHS
--                             only; class-A in-place waits never consume it).
--                             Budget = 3; exhaust → PARK (at-target) / ROLLBACK
--                             (pre-swap, data-safe).
--   recovery_parked_at      — when the row was parked (NULL = not parked). A
--                             parked row stays state='in_progress' (forward-only
--                             preserved; rollback stays reachable ONLY via a
--                             positively-Behind ground-truth verdict, never via
--                             exhaustion). The service SKIPS resume for a parked
--                             row and the degraded siren fires ONCE.
--   recovery_parked_reason  — the named, actionable reason (e.g. "migration
--                             <v> failed deterministically", "target image not
--                             published", "attempt budget exhausted at step X").
ALTER TABLE public.upgrade
  ADD COLUMN recovery_attempts      integer NOT NULL DEFAULT 0,
  ADD COLUMN recovery_parked_at     timestamptz,
  ADD COLUMN recovery_parked_reason text;

END;
