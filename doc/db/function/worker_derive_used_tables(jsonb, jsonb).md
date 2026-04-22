```sql
CREATE OR REPLACE PROCEDURE worker.derive_used_tables(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    p_info := jsonb_build_object('refreshed', jsonb_build_array(
        'activity_category_used', 'region_used', 'sector_used',
        'data_source_used', 'legal_form_used', 'country_used'
    ));
END;
$procedure$
```
