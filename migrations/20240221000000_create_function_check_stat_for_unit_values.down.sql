BEGIN;

DROP TRIGGER IF EXISTS check_stat_for_unit_values_trigger ON public.stat_for_unit;
DROP FUNCTION admin.check_stat_for_unit_values;

END;
