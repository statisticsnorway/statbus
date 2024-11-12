-- Create a view for region upload using path and name
\echo public.region_upload
CREATE VIEW public.region_upload
WITH (security_invoker=on) AS
SELECT path, name, center_latitude, center_longitude, center_altitude
FROM public.region
ORDER BY path;
COMMENT ON VIEW public.region_upload IS 'Upload of region by path,name that automatically connects parent_id';

\echo admin.region_upload_upsert
CREATE FUNCTION admin.region_upload_upsert()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- Create triggers for the view
CREATE TRIGGER region_upload_upsert
INSTEAD OF INSERT ON public.region_upload
FOR EACH ROW
EXECUTE FUNCTION admin.region_upload_upsert();


-- Custom functionality for Uganda
\echo admin.upsert_region_7_levels
CREATE FUNCTION admin.upsert_region_7_levels()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- Create a view for region
\echo public.region_7_levels_view
CREATE VIEW public.region_7_levels_view
WITH (security_invoker=on) AS
SELECT '' AS "Regional Code"
     , '' AS "Regional Name"
     , '' AS "District Code"
     , '' AS "District Name"
     , '' AS "County Code"
     , '' AS "County Name"
     , '' AS "Constituency Code"
     , '' AS "Constituency Name"
     , '' AS "Subcounty Code"
     , '' AS "Subcounty Name"
     , '' AS "Parish Code"
     , '' AS "Parish Name"
     , '' AS "Village Code"
     , '' AS "Village Name"
     ;

-- Create triggers for the view
CREATE TRIGGER upsert_region_7_levels_view
INSTEAD OF INSERT ON public.region_7_levels_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_region_7_levels();