-- Migration 20261008175729: statbus_479 sector custom upload reports the real unique violation
--
-- STATBUS-479. admin.sector_custom_only_upsert (the getting-started sector
-- upload) caught unique_violation and rebuilt the error as
--   '% for row %' with data := jsonb_set(data, '{code}', code::jsonb)
-- where code was the path's digits with a dot inserted after two. A path
-- without digits gave code '' and ''::jsonb failed, replacing the real
-- duplicate key with "invalid input syntax for type json"; a path with
-- digits reported a fabricated code ("11.10", parsed as a JSON number)
-- that is not the stored sector.code ("1110"). Either way the SQLSTATE
-- became P0001 and the constraint name and its key detail were lost.
-- The handler now re-raises the original error intact (SQLSTATE 23505,
-- constraint name, the original DETAIL) and adds the uploaded row's path
-- and name and a HINT for the constraint that was hit.
BEGIN;

CREATE OR REPLACE FUNCTION admin.sector_custom_only_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    maybe_parent_id int := NULL;
    row RECORD;
BEGIN
    -- Find parent sector based on NEW.path
    IF public.nlevel(NEW.path) > 1 THEN
        SELECT id INTO maybe_parent_id
          FROM public.sector
         WHERE path OPERATOR(public.=) public.subltree(NEW.path, 0, public.nlevel(NEW.path) - 1)
           AND enabled
           AND custom;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Could not find parent for path %', NEW.path;
        END IF;
        RAISE DEBUG 'maybe_parent_id %', maybe_parent_id;
    END IF;

    -- Perform an upsert operation on public.sector
    BEGIN
        INSERT INTO public.sector
            ( path
            , parent_id
            , name
            , description
            , updated_at
            , enabled
            , custom
            )
        VALUES
            ( NEW.path
            , maybe_parent_id
            , NEW.name
            , NEW.description
            , statement_timestamp()
            , TRUE -- Active
            , TRUE -- Custom
            )
        ON CONFLICT (path, enabled, custom)
        DO UPDATE SET
                parent_id = maybe_parent_id
              , name = NEW.name
              , description = NEW.description
              , updated_at = statement_timestamp()
              , enabled = TRUE
              , custom = TRUE
           RETURNING * INTO row;

        -- Log the upserted row
        RAISE DEBUG 'UPSERTED %', to_json(row);

    EXCEPTION WHEN unique_violation THEN
        DECLARE
            _constraint text;
            _detail text;
        BEGIN
            GET STACKED DIAGNOSTICS _constraint = CONSTRAINT_NAME, _detail = PG_EXCEPTION_DETAIL;
            -- The original message, SQLSTATE, constraint and DETAIL are kept
            -- exactly as PostgreSQL emitted them; the uploaded row is appended.
            -- (Under row level security PostgreSQL omits the key DETAIL; it is
            -- then omitted here too, and the appended path names the row.)
            -- A HINT is given only for the constraints whose meaning is known.
            IF _constraint IN ('sector_path_key', 'sector_code_enabled_key') AND _detail <> '' THEN
                RAISE EXCEPTION '% (uploaded sector path "%", name "%")', SQLERRM, NEW.path, NEW.name
                    USING ERRCODE = 'unique_violation'
                        , CONSTRAINT = _constraint
                        , DETAIL = _detail
                        , HINT = CASE _constraint
                            WHEN 'sector_path_key' THEN
                                'This path already exists as a standard (system) sector or earlier in the upload. Use a path that is not in the standard list, and list each path once.'
                            ELSE
                                'Another enabled sector already has the same code (the digits of the path). Give this sector a path whose digits differ.'
                          END;
            ELSIF _constraint IN ('sector_path_key', 'sector_code_enabled_key') THEN
                RAISE EXCEPTION '% (uploaded sector path "%", name "%")', SQLERRM, NEW.path, NEW.name
                    USING ERRCODE = 'unique_violation'
                        , CONSTRAINT = _constraint
                        , HINT = CASE _constraint
                            WHEN 'sector_path_key' THEN
                                'This path already exists as a standard (system) sector or earlier in the upload. Use a path that is not in the standard list, and list each path once.'
                            ELSE
                                'Another enabled sector already has the same code (the digits of the path). Give this sector a path whose digits differ.'
                          END;
            ELSIF _detail <> '' THEN
                RAISE EXCEPTION '% (uploaded sector path "%", name "%")', SQLERRM, NEW.path, NEW.name
                    USING ERRCODE = 'unique_violation'
                        , CONSTRAINT = coalesce(_constraint, '')
                        , DETAIL = _detail;
            ELSE
                RAISE EXCEPTION '% (uploaded sector path "%", name "%")', SQLERRM, NEW.path, NEW.name
                    USING ERRCODE = 'unique_violation'
                        , CONSTRAINT = coalesce(_constraint, '');
            END IF;
        END;
    END;

    RETURN NULL;
END;
$function$
;

END;
