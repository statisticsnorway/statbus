```sql
CREATE OR REPLACE FUNCTION admin.region_upload_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    maybe_parent_id int := NULL;
    row RECORD;
BEGIN
    IF public.nlevel(NEW.path) > 1 THEN
        SELECT id INTO maybe_parent_id
          FROM public.region
         WHERE path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1);

        IF NOT FOUND THEN
          RAISE EXCEPTION 'Could not find parent for path %', NEW.path;
        END IF;
        RAISE DEBUG 'maybe_parent_id %', maybe_parent_id;
    END IF;

    INSERT INTO public.region (path, parent_id, name, center_latitude, center_longitude, center_altitude)
    VALUES (NEW.path, maybe_parent_id, NEW.name, NEW.center_latitude, NEW.center_longitude, NEW.center_altitude)
    ON CONFLICT (path)
    DO UPDATE SET
        parent_id = maybe_parent_id,
        name = EXCLUDED.name,
        center_latitude = EXCLUDED.center_latitude,
        center_longitude = EXCLUDED.center_longitude,
        center_altitude = EXCLUDED.center_altitude
    WHERE region.id = EXCLUDED.id
    RETURNING * INTO row;
    RAISE DEBUG 'UPSERTED %', to_json(row);

    RETURN NULL;
END;
$function$
```
