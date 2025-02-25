BEGIN;

DROP FUNCTION IF EXISTS public.statistical_history_derive(date, date);
DROP TABLE IF EXISTS public.statistical_history;

END;
