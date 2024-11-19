\echo admin.process_enterprise_connection
CREATE FUNCTION admin.process_enterprise_connection(
    IN prior_unit_id INTEGER,
    IN unit_type TEXT,
    IN new_valid_from DATE,
    IN new_valid_to DATE,
    IN edited_by_user_id INTEGER,
    OUT enterprise_id INTEGER,
    OUT legal_unit_id INTEGER,
    OUT is_primary_for_enterprise BOOLEAN
) RETURNS RECORD LANGUAGE plpgsql AS $process_enterprise_connection$
DECLARE
    new_center DATE;
    order_clause TEXT;
BEGIN
    IF unit_type NOT IN ('legal_unit', 'establishment') THEN
        RAISE EXCEPTION 'Invalid unit_type: %', unit_type;
    END IF;

    IF prior_unit_id IS NOT NULL THEN
        -- Calculate the new center date, handling infinity.
        IF new_valid_from = '-infinity' THEN
            new_center := new_valid_to;
        ELSIF new_valid_to = 'infinity' THEN
            new_center := new_valid_from;
        ELSE
            new_center := new_valid_from + ((new_valid_to - new_valid_from) / 2);
        END IF;

        -- Find the closest enterprise connected to the prior legal unit or establishment, with consistent midpoint logic.
        order_clause := $$
            ORDER BY (
                CASE
                    WHEN valid_from = '-infinity' THEN ABS($2::DATE - valid_to)
                    WHEN valid_to = 'infinity' THEN ABS(valid_from - $2::DATE)
                    ELSE ABS($2::DATE - (valid_from + ((valid_to - valid_from) / 2))::DATE)
                END
            ) ASC
        $$;

        IF unit_type = 'establishment' THEN
            EXECUTE format($$
                SELECT enterprise_id, legal_unit_id
                FROM public.establishment
                WHERE id = $1
                %s
                LIMIT 1
            $$, order_clause)
            INTO enterprise_id, legal_unit_id
            USING prior_unit_id, new_center;

            IF enterprise_id IS NOT NULL THEN
              -- We allow multiple establishments per enterprise,
              -- i.e. grouping in the informal economy.
              EXECUTE $$
                  SELECT NOT EXISTS(
                      SELECT 1
                      FROM public.establishment
                      WHERE enterprise_id = $1
                      AND primary_for_enterprise
                      AND id <> $2
                      AND daterange(valid_from, valid_to, '[]')
                      && daterange($3, $4, '[]')
                  )
              $$
              INTO is_primary_for_enterprise
              USING enterprise_id, prior_unit_id, new_valid_from, new_valid_to;
            END IF;
        ELSIF unit_type = 'legal_unit' THEN
            EXECUTE format($$
                SELECT enterprise_id
                FROM public.legal_unit
                WHERE id = $1
                %s
                LIMIT 1
            $$, order_clause)
            INTO enterprise_id
            USING prior_unit_id, new_center;

            -- A legal_unit will always have an enterprise, so always check for primary.
            EXECUTE $$
                SELECT NOT EXISTS(
                    SELECT 1
                    FROM public.legal_unit
                    WHERE enterprise_id = $1
                    AND primary_for_enterprise
                    AND id <> $2
                    AND daterange(valid_from, valid_to, '[]')
                    && daterange($3, $4, '[]')
                )
            $$
            INTO is_primary_for_enterprise
            USING enterprise_id, prior_unit_id, new_valid_from, new_valid_to;
        END IF;
    ELSE -- prior_unit_id IS NULL
        -- Create a new enterprise and connect to it.
        INSERT INTO public.enterprise
            (active, edit_by_user_id, edit_comment)
        VALUES
            (true, edited_by_user_id, 'Batch import')
        RETURNING id INTO enterprise_id;

        -- This will be the primary legal unit or establishment for the enterprise.
        is_primary_for_enterprise := true;
    END IF;

    RETURN;
END;
$process_enterprise_connection$;

-- ========================================================
-- END:  Helper functions for import
-- ========================================================
