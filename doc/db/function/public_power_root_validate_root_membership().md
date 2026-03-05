```sql
CREATE OR REPLACE FUNCTION public.power_root_validate_root_membership()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    _invalid RECORD;
BEGIN
    -- derived_root must be influencing_id in some LR in the same PG
    SELECT nr.id, nr.power_group_id, nr.derived_root_legal_unit_id, nr.valid_range
    INTO _invalid
    FROM _new_power_root_rows AS nr
    WHERE NOT EXISTS (
        SELECT 1 FROM public.legal_relationship AS lr
        WHERE lr.derived_power_group_id = nr.power_group_id
          AND lr.influencing_id = nr.derived_root_legal_unit_id
          AND lr.valid_range && nr.valid_range
    )
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'power_root id=% has derived_root_legal_unit_id=% '
            'which is not an influencing LU in power_group % during %',
            _invalid.id, _invalid.derived_root_legal_unit_id,
            _invalid.power_group_id, _invalid.valid_range;
    END IF;

    -- custom_root (if set) must also be influencing_id in the PG
    SELECT nr.id, nr.power_group_id, nr.custom_root_legal_unit_id, nr.valid_range
    INTO _invalid
    FROM _new_power_root_rows AS nr
    WHERE nr.custom_root_legal_unit_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.legal_relationship AS lr
        WHERE lr.derived_power_group_id = nr.power_group_id
          AND lr.influencing_id = nr.custom_root_legal_unit_id
          AND lr.valid_range && nr.valid_range
    )
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'power_root id=% has custom_root_legal_unit_id=% '
            'which is not an influencing LU in power_group % during %',
            _invalid.id, _invalid.custom_root_legal_unit_id,
            _invalid.power_group_id, _invalid.valid_range;
    END IF;

    RETURN NULL;
END;
$function$
```
