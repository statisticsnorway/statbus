```sql
CREATE OR REPLACE FUNCTION admin.upsert_region_7_levels()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    WITH source AS (
        SELECT NEW."Regional Code"::ltree AS path, NEW."Regional Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree AS path, NEW."District Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code" AS path, NEW."County Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code" AS path, NEW."Constituency Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code"||NEW."Subcounty Code" AS path, NEW."Subcounty Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code"||NEW."Subcounty Code"||NEW."Parish Code" AS path, NEW."Parish Name" AS name
            UNION ALL
        SELECT NEW."Regional Code"::ltree||NEW."District Code"::ltree||NEW."County Code"||NEW."Constituency Code"||NEW."Subcounty Code"||NEW."Parish Code"||NEW."Village Code" AS path, NEW."Village Name" AS name
    )
    INSERT INTO public.region_view(path, name)
    SELECT path,name FROM source;
    RETURN NULL;
END;
$function$
```
