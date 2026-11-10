```sql
CREATE OR REPLACE PROCEDURE public.statistical_history_period_refresh()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    DELETE FROM public.statistical_history_period WHERE true; -- every row: rebuilt below from get_statistical_history_periods()
    INSERT INTO public.statistical_history_period (resolution, year, month, prev_stop, curr_start, curr_stop)
    SELECT resolution, year, month, prev_stop, curr_start, curr_stop FROM public.get_statistical_history_periods();
END;
$procedure$
```
