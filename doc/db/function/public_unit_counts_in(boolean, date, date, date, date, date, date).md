```sql
CREATE OR REPLACE FUNCTION public.unit_counts_in(status_counts boolean, valid_from date, valid_until date, birth_date date, death_date date, row_valid_from date, row_valid_until date)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT unit_counts_in.status_counts
       AND public.unit_existence_from(unit_counts_in.valid_from, unit_counts_in.birth_date) <= unit_counts_in.row_valid_from
       AND unit_counts_in.row_valid_until <= public.unit_existence_until(unit_counts_in.valid_until, unit_counts_in.death_date)
$function$
```
