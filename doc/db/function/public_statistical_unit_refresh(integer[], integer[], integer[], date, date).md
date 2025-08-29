```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_refresh(p_establishment_ids integer[] DEFAULT NULL::integer[], p_legal_unit_ids integer[] DEFAULT NULL::integer[], p_enterprise_ids integer[] DEFAULT NULL::integer[], p_valid_after date DEFAULT NULL::date, p_valid_to date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_valid_after date;
  v_valid_to date;
BEGIN
  -- Set the time range for filtering
  v_valid_after := COALESCE(p_valid_after, '-infinity'::date);
  v_valid_to := COALESCE(p_valid_to, 'infinity'::date);

  -- Create a temporary table to store the new data.
  CREATE TEMPORARY TABLE temp_statistical_unit AS
  SELECT * FROM public.statistical_unit_def AS sud
  WHERE (
    (p_establishment_ids IS NULL OR sud.related_establishment_ids && p_establishment_ids) OR
    (p_legal_unit_ids    IS NULL OR sud.related_legal_unit_ids && p_legal_unit_ids) OR
    (p_enterprise_ids    IS NULL OR sud.related_enterprise_ids && p_enterprise_ids)
  )
  AND after_to_overlaps(sud.valid_after, sud.valid_to, v_valid_after, v_valid_to);

  -- Delete ALL existing records for any unit related to the change within the given time range.
  -- This "scorched earth" approach prevents exclusion constraint violations and ensures
  -- that units that cease to exist are properly removed.
  DELETE FROM public.statistical_unit su
  WHERE (
    (p_establishment_ids IS NULL OR su.related_establishment_ids && p_establishment_ids) OR
    (p_legal_unit_ids    IS NULL OR su.related_legal_unit_ids && p_legal_unit_ids) OR
    (p_enterprise_ids    IS NULL OR su.related_enterprise_ids && p_enterprise_ids)
  )
  AND after_to_overlaps(su.valid_after, su.valid_to, v_valid_after, v_valid_to);

  -- Perform a simple INSERT. ON CONFLICT is no longer needed because we have cleared the way.
  INSERT INTO public.statistical_unit
  SELECT * FROM temp_statistical_unit;

  DROP TABLE temp_statistical_unit;
  ANALYZE public.statistical_unit;
END;
$function$
```
