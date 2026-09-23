```sql
CREATE OR REPLACE FUNCTION public.upgrade_version_key(p_version text)
 RETURNS integer[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $function$
    SELECT CASE
        WHEN match IS NULL THEN NULL
        ELSE ARRAY[
            match[1]::integer,
            match[2]::integer,
            match[3]::integer,
            CASE WHEN match[4] IS NULL THEN 1 ELSE 0 END,
            COALESCE(match[4]::integer, 0)
        ]
    END
    FROM regexp_match(
        p_version,
        '^v+([0-9]{4})\.([0-9]{2})\.([0-9]+)(?:-rc\.([0-9]+))?$'
    ) AS match;
$function$
```
