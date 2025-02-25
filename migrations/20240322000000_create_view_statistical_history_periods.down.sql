BEGIN;

DROP FUNCTION public.get_statistical_history_periods(public.history_resolution, date, date);

DROP TYPE public.history_resolution;

END;
