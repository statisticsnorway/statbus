```sql
CREATE OR REPLACE PROCEDURE public.history_period_refresh()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    DELETE FROM public.history_period;
    INSERT INTO public.history_period (resolution, year, month, prev_stop, curr_start, curr_stop)
    SELECT resolution, year, month, prev_stop, curr_start, curr_stop FROM public.get_statistical_history_periods();
END;
$procedure$
```
