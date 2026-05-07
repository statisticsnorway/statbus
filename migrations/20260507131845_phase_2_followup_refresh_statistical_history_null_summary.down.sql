-- Down migration 20260507131845: re-run the same cleanup (idempotent).
--
-- The up migration corrected stale NULL-summary inflation. There is no
-- way to "undo" the correction without re-introducing the inflation by
-- running the original buggy code — which we won't.
--
-- Re-runs the wipe + re-derive + reduce on rollback for symmetry with
-- Phase 3's down migration. Idempotent — safe to run any time the
-- procedures are at HEAD.

BEGIN;

TRUNCATE public.statistical_history;

INSERT INTO public.statistical_history
SELECT h.*
  FROM public.get_statistical_history_periods(
           p_resolution := null::public.history_resolution,
           p_valid_from := '-infinity'::date,
           p_valid_until := 'infinity'::date) AS tp
  CROSS JOIN LATERAL public.statistical_history_def(tp.resolution, tp.year, tp.month) AS h;

CALL worker.statistical_history_reduce('{}'::jsonb);

END;
