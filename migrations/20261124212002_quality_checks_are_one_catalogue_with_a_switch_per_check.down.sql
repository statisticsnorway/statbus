-- Down of migration 20261124212002: the table per quality check comes back (definitions as made by
-- migrations 20261118134950 and 20261124115435), the catalogue and its findings go, and the
-- functions that named them are restored as they were before the up migration.
BEGIN;

CREATE TABLE public.quality_establishment_activity_differs (
    unit_type public.statistical_unit_type NOT NULL,
    unit_id integer NOT NULL,
    valid_from date NOT NULL,
    valid_until date NOT NULL,
    valid_range daterange NOT NULL GENERATED ALWAYS AS (daterange(valid_from, valid_until)) STORED,
    legal_unit_activity_category_id integer,
    primary_establishment_id integer NOT NULL,
    primary_establishment_activity_category_id integer,
    CONSTRAINT quality_establishment_activity_differs_pkey
        PRIMARY KEY (unit_type, unit_id, valid_range),
    CONSTRAINT quality_establishment_activity_differs_statistical_unit_fkey
        FOREIGN KEY (unit_type, unit_id, PERIOD valid_range)
        REFERENCES public.statistical_unit (unit_type, unit_id, PERIOD valid_range) NOT ENFORCED
);

COMMENT ON TABLE public.quality_establishment_activity_differs IS
  'Quality check (xz3jej): one row per legal_unit row of statistical_unit whose primary activity category differs from that of its primary establishment (timeline_establishment.primary_for_legal_unit) valid at the row''s valid_from, compared by id, a missing activity on one side counting as a difference. Uses the primary as recorded and never picks one. Filled from quality_establishment_activity_differs_def by quality_establishment_activity_differs_derive(), which worker.derive_quality calls after statistical_unit is published. The dashboard''s Data quality card counts it and the search lists it as select=*,quality_establishment_activity_differs!inner().';
COMMENT ON COLUMN public.quality_establishment_activity_differs.valid_range IS
  'The statistical_unit row''s period. With unit_type and unit_id it is both the primary key and the foreign key to statistical_unit, so PostgREST sees a one-to-one relationship and embeds it as a plain join; another primary key makes it one-to-many, aggregated as JSON per row.';
COMMENT ON CONSTRAINT quality_establishment_activity_differs_statistical_unit_fkey ON public.quality_establishment_activity_differs IS
  'NOT ENFORCED: describes the link for PostgREST and readers; nothing checks it, so derive rewrites statistical_unit freely and the table is made right again by the next worker.derive_quality. Until then a row whose statistical_unit period changed drops out of the inner join. A TRUNCATE of statistical_unit must name this table and say CASCADE: TRUNCATE refuses a NOT ENFORCED key otherwise, even with both tables listed (PostgreSQL 18).';
COMMENT ON COLUMN public.quality_establishment_activity_differs.legal_unit_activity_category_id IS
  'The legal unit''s primary activity category (statistical_unit.primary_activity_category_id), NULL when it has none.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.primary_establishment_id IS
  'The establishment recorded as the legal unit''s primary at valid_from.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.primary_establishment_activity_category_id IS
  'The primary establishment''s primary activity category at valid_from, NULL when it has none.';

CREATE VIEW public.quality_establishment_activity_differs_def
WITH (security_invoker = on) AS
SELECT su.unit_type,
       su.unit_id,
       su.valid_from,
       su.valid_until,
       su.primary_activity_category_id AS legal_unit_activity_category_id,
       te.unit_id AS primary_establishment_id,
       te.primary_activity_category_id AS primary_establishment_activity_category_id
FROM public.statistical_unit AS su
JOIN public.timeline_establishment AS te
  ON te.legal_unit_id = su.unit_id
 AND te.primary_for_legal_unit
 AND te.valid_from <= su.valid_from AND su.valid_from < te.valid_until
WHERE su.unit_type = 'legal_unit'
  AND su.primary_activity_category_id IS DISTINCT FROM te.primary_activity_category_id;

COMMENT ON VIEW public.quality_establishment_activity_differs_def IS
  'The rule of the quality check public.quality_establishment_activity_differs, read from statistical_unit and timeline_establishment.';

GRANT SELECT ON public.quality_establishment_activity_differs_def TO authenticated, regular_user, admin_user;

CREATE FUNCTION public.quality_establishment_activity_differs_derive()
RETURNS void
LANGUAGE plpgsql
AS $quality_establishment_activity_differs_derive$
BEGIN
    RAISE DEBUG 'Running quality_establishment_activity_differs_derive()';
    MERGE INTO public.quality_establishment_activity_differs AS target
    USING public.quality_establishment_activity_differs_def AS source
    ON target.unit_type = source.unit_type
   AND target.unit_id = source.unit_id
   AND target.valid_range = daterange(source.valid_from, source.valid_until)
    WHEN MATCHED AND (
        target.legal_unit_activity_category_id IS DISTINCT FROM source.legal_unit_activity_category_id
        OR target.primary_establishment_id IS DISTINCT FROM source.primary_establishment_id
        OR target.primary_establishment_activity_category_id IS DISTINCT FROM source.primary_establishment_activity_category_id
    ) THEN UPDATE SET
        legal_unit_activity_category_id = source.legal_unit_activity_category_id,
        primary_establishment_id = source.primary_establishment_id,
        primary_establishment_activity_category_id = source.primary_establishment_activity_category_id
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (unit_type, unit_id, valid_from, valid_until, legal_unit_activity_category_id,
         primary_establishment_id, primary_establishment_activity_category_id)
        VALUES (source.unit_type, source.unit_id, source.valid_from, source.valid_until,
                source.legal_unit_activity_category_id, source.primary_establishment_id,
                source.primary_establishment_activity_category_id)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    ANALYZE public.quality_establishment_activity_differs;
END;
$quality_establishment_activity_differs_derive$;

COMMENT ON FUNCTION public.quality_establishment_activity_differs_derive() IS
  'Makes the quality check public.quality_establishment_activity_differs equal to its _def view (insert, update, delete); called by worker.derive_quality.';

SELECT admin.add_rls_regular_user_can_read('public.quality_establishment_activity_differs'::regclass);

-- ######## quality_establishments_above_legal_unit ########
CREATE TABLE public.quality_establishments_above_legal_unit (
    unit_type public.statistical_unit_type NOT NULL,
    unit_id integer NOT NULL,
    valid_from date NOT NULL,
    valid_until date NOT NULL,
    valid_range daterange NOT NULL GENERATED ALWAYS AS (daterange(valid_from, valid_until)) STORED,
    stats jsonb NOT NULL,
    CONSTRAINT quality_establishments_above_legal_unit_pkey
        PRIMARY KEY (unit_type, unit_id, valid_range),
    CONSTRAINT quality_establishments_above_legal_unit_statistical_unit_fkey
        FOREIGN KEY (unit_type, unit_id, PERIOD valid_range)
        REFERENCES public.statistical_unit (unit_type, unit_id, PERIOD valid_range) NOT ENFORCED
);

COMMENT ON TABLE public.quality_establishments_above_legal_unit IS
  'Quality check (ca6dk5): one row per legal_unit row of statistical_unit where, for at least one summed stat, the legal unit has its own value and its counted establishments'' values add up to more. Establishments are parts of their legal unit (UN Guidelines on Statistical Business Registers; Eurostat Business Registers Recommendations Manual), so the parts exceeding the whole is a reporting error on one level; the legal unit''s total takes the establishments'' sum (public.jsonb_stats_covers). Filled from quality_establishments_above_legal_unit_def by quality_legal_unit_establishments_derive() in worker.derive_quality. Search lists it as select=*,quality_establishments_above_legal_unit!inner().';
COMMENT ON COLUMN public.quality_establishments_above_legal_unit.valid_range IS
  'The statistical_unit row''s period. With unit_type and unit_id it is both the primary key and the foreign key to statistical_unit, so PostgREST embeds it as a one-to-one relationship.';
COMMENT ON CONSTRAINT quality_establishments_above_legal_unit_statistical_unit_fkey ON public.quality_establishments_above_legal_unit IS
  'NOT ENFORCED: describes the link for PostgREST and readers; derive rewrites statistical_unit freely and the next worker.derive_quality makes this table right again. A TRUNCATE of statistical_unit names this table and says CASCADE.';
COMMENT ON COLUMN public.quality_establishments_above_legal_unit.stats IS
  'Per stat code found: {"legal_unit": own value, "establishments_sum": sum, "establishments": count}, e.g. {"employees": {"legal_unit": 989, "establishments_sum": 1055, "establishments": 19}}.';

CREATE VIEW public.quality_establishments_above_legal_unit_def
WITH (security_invoker = on) AS
SELECT c.unit_type,
       c.unit_id,
       c.valid_from,
       c.valid_until,
       jsonb_object_agg(c.stat_code, jsonb_build_object(
           'legal_unit', c.legal_unit_value,
           'establishments_sum', c.establishments_sum,
           'establishments', c.establishment_count)) AS stats
FROM public.legal_unit_establishment_stat_comparison AS c
WHERE c.legal_unit_value < c.establishments_sum
GROUP BY c.unit_type, c.unit_id, c.valid_from, c.valid_until;

COMMENT ON VIEW public.quality_establishments_above_legal_unit_def IS
  'The rule of the quality check public.quality_establishments_above_legal_unit: a summed stat where the legal unit''s own value is below its counted establishments'' sum.';
GRANT SELECT ON public.quality_establishments_above_legal_unit_def TO authenticated, regular_user, admin_user;

SELECT admin.add_rls_regular_user_can_read('public.quality_establishments_above_legal_unit'::regclass);

-- ######## quality_legal_unit_above_establishments ########
CREATE TABLE public.quality_legal_unit_above_establishments (
    unit_type public.statistical_unit_type NOT NULL,
    unit_id integer NOT NULL,
    valid_from date NOT NULL,
    valid_until date NOT NULL,
    valid_range daterange NOT NULL GENERATED ALWAYS AS (daterange(valid_from, valid_until)) STORED,
    stats jsonb NOT NULL,
    CONSTRAINT quality_legal_unit_above_establishments_pkey
        PRIMARY KEY (unit_type, unit_id, valid_range),
    CONSTRAINT quality_legal_unit_above_establishments_statistical_unit_fkey
        FOREIGN KEY (unit_type, unit_id, PERIOD valid_range)
        REFERENCES public.statistical_unit (unit_type, unit_id, PERIOD valid_range) NOT ENFORCED
);

COMMENT ON TABLE public.quality_legal_unit_above_establishments IS
  'Quality check (ca6dk5): one row per legal_unit row of statistical_unit where, for at least one summed stat, the legal unit''s own value is larger than its counted establishments'' sum while every one of those establishments has a value. The legal unit''s value covers its establishments (UN Guidelines on Statistical Business Registers; Eurostat Business Registers Recommendations Manual), so the rest belongs to an establishment, yet none lacks a value: often an establishment, such as the head office, is missing. A legal unit that is larger while some establishments have no value is not listed, as its own value covers them. Filled from quality_legal_unit_above_establishments_def by quality_legal_unit_establishments_derive() in worker.derive_quality. Search lists it as select=*,quality_legal_unit_above_establishments!inner().';
COMMENT ON COLUMN public.quality_legal_unit_above_establishments.valid_range IS
  'The statistical_unit row''s period. With unit_type and unit_id it is both the primary key and the foreign key to statistical_unit, so PostgREST embeds it as a one-to-one relationship.';
COMMENT ON CONSTRAINT quality_legal_unit_above_establishments_statistical_unit_fkey ON public.quality_legal_unit_above_establishments IS
  'NOT ENFORCED: describes the link for PostgREST and readers; derive rewrites statistical_unit freely and the next worker.derive_quality makes this table right again. A TRUNCATE of statistical_unit names this table and says CASCADE.';
COMMENT ON COLUMN public.quality_legal_unit_above_establishments.stats IS
  'Per stat code found: {"legal_unit": own value, "establishments_sum": sum, "establishments": count}, e.g. {"employees": {"legal_unit": 364, "establishments_sum": 5, "establishments": 1}}.';

CREATE VIEW public.quality_legal_unit_above_establishments_def
WITH (security_invoker = on) AS
SELECT c.unit_type,
       c.unit_id,
       c.valid_from,
       c.valid_until,
       jsonb_object_agg(c.stat_code, jsonb_build_object(
           'legal_unit', c.legal_unit_value,
           'establishments_sum', c.establishments_sum,
           'establishments', c.establishment_count)) AS stats
FROM public.legal_unit_establishment_stat_comparison AS c
WHERE c.establishments_sum < c.legal_unit_value
  AND c.establishments_with_value = c.establishment_count
GROUP BY c.unit_type, c.unit_id, c.valid_from, c.valid_until;

COMMENT ON VIEW public.quality_legal_unit_above_establishments_def IS
  'The rule of the quality check public.quality_legal_unit_above_establishments: a summed stat where the legal unit''s own value is above its counted establishments'' sum and every one of them has a value.';
GRANT SELECT ON public.quality_legal_unit_above_establishments_def TO authenticated, regular_user, admin_user;

SELECT admin.add_rls_regular_user_can_read('public.quality_legal_unit_above_establishments'::regclass);

-- ######## one derive for both checks: the comparison is read once ########
CREATE FUNCTION public.quality_legal_unit_establishments_derive()
RETURNS void
LANGUAGE plpgsql
AS $quality_legal_unit_establishments_derive$
BEGIN
    RAISE DEBUG 'Running quality_legal_unit_establishments_derive()';
    IF to_regclass('pg_temp.legal_unit_establishment_stat_comparison_now') IS NOT NULL THEN
        DROP TABLE legal_unit_establishment_stat_comparison_now;
    END IF;
    CREATE TEMP TABLE legal_unit_establishment_stat_comparison_now ON COMMIT DROP AS
    SELECT * FROM public.legal_unit_establishment_stat_comparison;

    MERGE INTO public.quality_establishments_above_legal_unit AS target
    USING (
        SELECT c.unit_type, c.unit_id, c.valid_from, c.valid_until,
               jsonb_object_agg(c.stat_code, jsonb_build_object(
                   'legal_unit', c.legal_unit_value,
                   'establishments_sum', c.establishments_sum,
                   'establishments', c.establishment_count)) AS stats
        FROM legal_unit_establishment_stat_comparison_now AS c
        WHERE c.legal_unit_value < c.establishments_sum
        GROUP BY c.unit_type, c.unit_id, c.valid_from, c.valid_until
    ) AS source
    ON target.unit_type = source.unit_type
   AND target.unit_id = source.unit_id
   AND target.valid_range = daterange(source.valid_from, source.valid_until)
    WHEN MATCHED AND target.stats IS DISTINCT FROM source.stats THEN UPDATE SET stats = source.stats
    WHEN NOT MATCHED BY TARGET THEN INSERT (unit_type, unit_id, valid_from, valid_until, stats)
        VALUES (source.unit_type, source.unit_id, source.valid_from, source.valid_until, source.stats)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    ANALYZE public.quality_establishments_above_legal_unit;

    MERGE INTO public.quality_legal_unit_above_establishments AS target
    USING (
        SELECT c.unit_type, c.unit_id, c.valid_from, c.valid_until,
               jsonb_object_agg(c.stat_code, jsonb_build_object(
                   'legal_unit', c.legal_unit_value,
                   'establishments_sum', c.establishments_sum,
                   'establishments', c.establishment_count)) AS stats
        FROM legal_unit_establishment_stat_comparison_now AS c
        WHERE c.establishments_sum < c.legal_unit_value
          AND c.establishments_with_value = c.establishment_count
        GROUP BY c.unit_type, c.unit_id, c.valid_from, c.valid_until
    ) AS source
    ON target.unit_type = source.unit_type
   AND target.unit_id = source.unit_id
   AND target.valid_range = daterange(source.valid_from, source.valid_until)
    WHEN MATCHED AND target.stats IS DISTINCT FROM source.stats THEN UPDATE SET stats = source.stats
    WHEN NOT MATCHED BY TARGET THEN INSERT (unit_type, unit_id, valid_from, valid_until, stats)
        VALUES (source.unit_type, source.unit_id, source.valid_from, source.valid_until, source.stats)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    ANALYZE public.quality_legal_unit_above_establishments;
END;
$quality_legal_unit_establishments_derive$;

COMMENT ON FUNCTION public.quality_legal_unit_establishments_derive() IS
  'Makes public.quality_establishments_above_legal_unit and public.quality_legal_unit_above_establishments equal to their _def views (insert, update, delete), reading public.legal_unit_establishment_stat_comparison once for both (Norway register, 2026-11-24: 14 s for both); called by worker.derive_quality.';


-- worker.derive_quality, statistical_unit_refresh, reset and apply_rls_to_all_tables as before.
COMMENT ON VIEW public.legal_unit_establishment_stat_comparison IS
  'Per legal_unit row of statistical_unit and enabled summed stat (int, float) held both by the legal unit and by at least one counted establishment: the legal unit''s own value (statistical_unit.stats) and its counted establishments'' count, count with a value, and sum at the row''s valid_from. The rules of quality_establishments_above_legal_unit and quality_legal_unit_above_establishments read it; a legal unit''s total takes the larger level (public.jsonb_stats_covers).';
CREATE OR REPLACE PROCEDURE worker.derive_quality(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    PERFORM public.quality_establishment_activity_differs_derive();
    PERFORM public.quality_legal_unit_establishments_derive();

    p_info := jsonb_build_object('checks', jsonb_build_array(
        'quality_establishment_activity_differs',
        'quality_establishments_above_legal_unit',
        'quality_legal_unit_above_establishments'
    ));
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE public.statistical_unit_refresh(IN p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, IN p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_batch_size INT := 262144;
    v_min_id int; v_max_id int; v_start_id int; v_end_id int;
    v_batch_num INT; v_total_units INT;
    v_batch_start_time timestamptz; v_batch_duration_ms numeric; v_batch_speed numeric; v_current_batch_size int;
    v_is_partial_refresh BOOLEAN;
    v_col_list TEXT;
BEGIN
    v_is_partial_refresh := (p_establishment_id_ranges IS NOT NULL
                            OR p_legal_unit_id_ranges IS NOT NULL
                            OR p_enterprise_id_ranges IS NOT NULL
                            OR p_power_group_id_ranges IS NOT NULL);

    -- Column list used for all INSERT statements (excludes GENERATED valid_range)
    v_col_list := 'unit_type, unit_id, valid_from, valid_to, valid_until, external_idents, name, birth_date, death_date, search,
        primary_activity_category_id, primary_activity_category_path, primary_activity_category_code,
        secondary_activity_category_id, secondary_activity_category_path, secondary_activity_category_code,
        activity_category_paths, sector_id, sector_path, sector_code, sector_name,
        data_source_ids, data_source_codes, legal_form_id, legal_form_code, legal_form_name,
        physical_address_part1, physical_address_part2, physical_address_part3, physical_postcode, physical_postplace,
        physical_region_id, physical_region_path, physical_region_code, physical_country_id, physical_country_iso_2,
        physical_latitude, physical_longitude, physical_altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
        postal_latitude, postal_longitude, postal_altitude,
        web_address, email_address, phone_number, landline, mobile_number, fax_number,
        unit_size_id, unit_size_code, status_id, status_code, used_for_counting,
        last_edit_comment, last_edit_by_user_id, last_edit_at, has_legal_unit,
        related_establishment_ids, excluded_establishment_ids, included_establishment_ids,
        related_legal_unit_ids, excluded_legal_unit_ids, included_legal_unit_ids,
        related_enterprise_ids, excluded_enterprise_ids, included_enterprise_ids,
        stats, stats_summary, included_establishment_count, included_legal_unit_count, included_enterprise_count, tag_paths';

    IF NOT v_is_partial_refresh THEN
        ANALYZE public.timeline_establishment, public.timeline_legal_unit, public.timeline_enterprise, public.timeline_power_group;
        CREATE TEMP TABLE statistical_unit_new (LIKE public.statistical_unit) ON COMMIT DROP;
        ALTER TABLE statistical_unit_new DROP COLUMN IF EXISTS valid_range;

        -- Establishments
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'establishment';
        RAISE DEBUG 'Refreshing statistical units for % establishments...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'establishment', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Legal Units
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'legal_unit';
        RAISE DEBUG 'Refreshing statistical units for % legal units...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'legal_unit', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Enterprises
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'enterprise';
        RAISE DEBUG 'Refreshing statistical units for % enterprises...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'enterprise', v_start_id, v_end_id);
        END LOOP; END IF;

        -- Power Groups
        v_batch_num := 0;
        SELECT MIN(unit_id), MAX(unit_id), COUNT(unit_id) INTO v_min_id, v_max_id, v_total_units FROM public.timesegments WHERE unit_type = 'power_group';
        RAISE DEBUG 'Refreshing statistical units for % power groups...', v_total_units;
        IF v_min_id IS NOT NULL THEN FOR i IN v_min_id..v_max_id BY v_batch_size LOOP
            v_batch_num := v_batch_num + 1; v_start_id := i; v_end_id := i + v_batch_size - 1;
            EXECUTE format('INSERT INTO statistical_unit_new (%s) SELECT %s FROM public.statistical_unit_def WHERE unit_type = %L AND unit_id BETWEEN %s AND %s', v_col_list, v_col_list, 'power_group', v_start_id, v_end_id);
        END LOOP; END IF;

        -- The quality checks (public.quality_*) point at the rows replaced here and are refilled by
        -- the next worker.derive_quality. It references statistical_unit by a NOT ENFORCED foreign
        -- key, which TRUNCATE refuses without CASCADE even with both tables listed.
        TRUNCATE public.statistical_unit, public.quality_establishment_activity_differs,
                 public.quality_establishments_above_legal_unit, public.quality_legal_unit_above_establishments CASCADE;
        EXECUTE format('INSERT INTO public.statistical_unit (%s) SELECT %s FROM statistical_unit_new', v_col_list, v_col_list);
        ANALYZE public.statistical_unit;
    ELSE
        -- Partial refresh: Write to staging table
        IF p_establishment_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'establishment' AND unit_id = ANY(public.int4multirange_to_array(p_establishment_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'establishment', p_establishment_id_ranges::text);
        END IF;
        IF p_legal_unit_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'legal_unit' AND unit_id = ANY(public.int4multirange_to_array(p_legal_unit_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'legal_unit', p_legal_unit_id_ranges::text);
        END IF;
        IF p_enterprise_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'enterprise' AND unit_id = ANY(public.int4multirange_to_array(p_enterprise_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'enterprise', p_enterprise_id_ranges::text);
        END IF;
        IF p_power_group_id_ranges IS NOT NULL THEN
            DELETE FROM public.statistical_unit_staging WHERE unit_type = 'power_group' AND unit_id = ANY(public.int4multirange_to_array(p_power_group_id_ranges));
            EXECUTE format('INSERT INTO public.statistical_unit_staging (%s) SELECT %s FROM import.get_statistical_unit_data_partial(%L, %L::int4multirange)', v_col_list, v_col_list, 'power_group', p_power_group_id_ranges::text);
        END IF;
    END IF;
END;
$procedure$
;

CREATE OR REPLACE FUNCTION public.reset(confirmed boolean, scope reset_scope)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    result JSONB := '{}'::JSONB;
    changed JSONB;
    _activity_count bigint;
    _location_count bigint;
    _contact_count bigint;
    _person_for_unit_count bigint;
    _person_count bigint;
    _tag_for_unit_count bigint;
    _stat_for_unit_count bigint;
    _external_ident_count bigint;
    _legal_relationship_count bigint;
    _power_root_count bigint;
    _establishment_count bigint;
    _legal_unit_count bigint;
    _enterprise_count bigint;
    _power_group_count bigint;
    _image_count bigint;
    _unit_notes_count bigint;
BEGIN
    IF NOT confirmed THEN
        RAISE EXCEPTION 'Action not confirmed.';
    END IF;

    -- Scope: units (and every broader scope): the statistical units and the import jobs that made them
    -- ================================================================

    CASE WHEN scope IN ('units', 'getting-started', 'customisation') THEN
        SELECT COUNT(*) FROM public.activity INTO _activity_count;
        SELECT COUNT(*) FROM public.location INTO _location_count;
        SELECT COUNT(*) FROM public.contact INTO _contact_count;
        SELECT COUNT(*) FROM public.person_for_unit INTO _person_for_unit_count;
        SELECT COUNT(*) FROM public.person INTO _person_count;
        SELECT COUNT(*) FROM public.tag_for_unit INTO _tag_for_unit_count;
        SELECT COUNT(*) FROM public.stat_for_unit INTO _stat_for_unit_count;
        SELECT COUNT(*) FROM public.external_ident INTO _external_ident_count;
        SELECT COUNT(*) FROM public.legal_relationship INTO _legal_relationship_count;
        SELECT COUNT(*) FROM public.power_root INTO _power_root_count;
        SELECT COUNT(*) FROM public.establishment INTO _establishment_count;
        SELECT COUNT(*) FROM public.legal_unit INTO _legal_unit_count;
        SELECT COUNT(*) FROM public.enterprise INTO _enterprise_count;
        SELECT COUNT(*) FROM public.power_group INTO _power_group_count;
        SELECT COUNT(*) FROM public.image INTO _image_count;
        SELECT COUNT(*) FROM public.unit_notes INTO _unit_notes_count;

        -- statistical_unit is emptied together with the quality checks (public.quality_*), which
        -- references it by a NOT ENFORCED foreign key: TRUNCATE refuses such a key without CASCADE,
        -- even with both tables listed. CASCADE is kept to this statement so that a new enforced
        -- key to any table in the list below still stops reset instead of emptying its table.
        TRUNCATE public.statistical_unit, public.quality_establishment_activity_differs,
                 public.quality_establishments_above_legal_unit, public.quality_legal_unit_above_establishments CASCADE;

        TRUNCATE
            public.activity,
            public.location,
            public.contact,
            public.stat_for_unit,
            public.external_ident,
            public.person_for_unit,
            public.person,
            public.tag_for_unit,
            public.unit_notes,
            public.legal_relationship,
            public.power_root,
            public.establishment,
            public.legal_unit,
            public.enterprise,
            public.power_group,
            public.image,
            public.timeline_establishment,
            public.timeline_legal_unit,
            public.timeline_enterprise,
            public.timeline_power_group,
            public.timepoints,
            public.timesegments,
            public.timesegments_years,
            public.statistical_unit_facet,
            public.statistical_unit_facet_staging,
            public.statistical_unit_facet_dirty_hash_slots,
            public.statistical_history_facet_delta,
            public.statistical_history_facet_delta_staging,
            public.statistical_history_period;

        result := result
            || jsonb_build_object('activity', jsonb_build_object('deleted_count', _activity_count))
            || jsonb_build_object('location', jsonb_build_object('deleted_count', _location_count))
            || jsonb_build_object('contact', jsonb_build_object('deleted_count', _contact_count))
            || jsonb_build_object('person_for_unit', jsonb_build_object('deleted_count', _person_for_unit_count))
            || jsonb_build_object('person', jsonb_build_object('deleted_count', _person_count))
            || jsonb_build_object('tag_for_unit', jsonb_build_object('deleted_count', _tag_for_unit_count))
            || jsonb_build_object('stat_for_unit', jsonb_build_object('deleted_count', _stat_for_unit_count))
            || jsonb_build_object('external_ident', jsonb_build_object('deleted_count', _external_ident_count))
            || jsonb_build_object('legal_relationship', jsonb_build_object('deleted_count', _legal_relationship_count))
            || jsonb_build_object('power_root', jsonb_build_object('deleted_count', _power_root_count))
            || jsonb_build_object('establishment', jsonb_build_object('deleted_count', _establishment_count))
            || jsonb_build_object('legal_unit', jsonb_build_object('deleted_count', _legal_unit_count))
            || jsonb_build_object('enterprise', jsonb_build_object('deleted_count', _enterprise_count))
            || jsonb_build_object('power_group', jsonb_build_object('deleted_count', _power_group_count))
            || jsonb_build_object('image', jsonb_build_object('deleted_count', _image_count))
            || jsonb_build_object('unit_notes', jsonb_build_object('deleted_count', _unit_notes_count));
    ELSE END CASE;

    CASE WHEN scope IN ('units', 'getting-started', 'customisation') THEN
        WITH deleted_import_job AS (
            DELETE FROM public.import_job WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'import_job', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_import_job)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- ================================================================
    -- Scope: getting-started: the steps of the Getting started menu
    -- ================================================================

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        -- Transient: delete custom definitions before data_source due to RESTRICT FK. See doc/data-model.md
        WITH deleted_import_definition AS (
            DELETE FROM public.import_definition WHERE custom RETURNING *
        )
        SELECT jsonb_build_object(
            'import_definition', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_import_definition)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        WITH deleted_region AS (
            DELETE FROM public.region WHERE id > 0 RETURNING *
        )
        SELECT jsonb_build_object(
            'region', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_region)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        WITH deleted_settings AS (
            DELETE FROM public.settings WHERE only_one_setting = TRUE RETURNING *
        )
        SELECT jsonb_build_object(
            'settings', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_settings)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        WITH deleted_rv AS (
            DELETE FROM public.region_version WHERE custom RETURNING *
        ), changed_rv AS (
            UPDATE public.region_version SET enabled = TRUE
             WHERE NOT custom AND NOT enabled RETURNING *
        )
        SELECT jsonb_build_object('region_version', jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_rv),
            'changed_count', (SELECT COUNT(*) FROM changed_rv)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        WITH activity_category_to_delete AS (
            SELECT to_delete.id AS id_to_delete
                 , replacement.id AS replacement_id
            FROM public.activity_category AS to_delete
            LEFT JOIN public.activity_category AS replacement
              ON to_delete.path = replacement.path
             AND to_delete.standard_id = replacement.standard_id
             AND NOT replacement.custom
            WHERE to_delete.custom
              AND to_delete.enabled
            ORDER BY to_delete.path
        ), updated_child AS (
            UPDATE public.activity_category AS child
               SET parent_id = to_delete.replacement_id
              FROM activity_category_to_delete AS to_delete
               WHERE to_delete.replacement_id IS NOT NULL
                 AND NOT child.custom
                 AND parent_id = to_delete.id_to_delete
            RETURNING *
        ), deleted_activity_category AS (
            DELETE FROM public.activity_category
             WHERE id in (SELECT id_to_delete FROM activity_category_to_delete)
            RETURNING *
        )
        SELECT jsonb_build_object(
            'deleted_count', (SELECT COUNT(*) FROM deleted_activity_category),
            'changed_children_count', (SELECT COUNT(*) FROM updated_child)
        ) INTO changed;

        WITH changed_activity_category AS (
            UPDATE public.activity_category
            SET enabled = TRUE
            WHERE NOT custom
              AND NOT enabled
            RETURNING *
        )
        SELECT changed || jsonb_build_object(
            'changed_count', (SELECT COUNT(*) FROM changed_activity_category)
        ) INTO changed;
        SELECT jsonb_build_object('activity_category', changed) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        -- The activity category standards as shipped; restoring code_pattern
        -- re-derives the codes (trigger recalculate_activity_category_codes).
        WITH restored AS (
            UPDATE public.activity_category_standard AS t
               SET name = fd.name, description = fd.description, code_pattern = fd.code_pattern,
                   enabled = fd.enabled, lasts_to = fd.lasts_to
              FROM public.activity_category_standard_factory_default AS fd
             WHERE t.code = fd.code
               AND (t.name IS DISTINCT FROM fd.name OR t.description IS DISTINCT FROM fd.description
                    OR t.code_pattern IS DISTINCT FROM fd.code_pattern OR t.enabled IS DISTINCT FROM fd.enabled
                    OR t.lasts_to IS DISTINCT FROM fd.lasts_to)
            RETURNING 1
        )
        SELECT jsonb_build_object('activity_category_standard', jsonb_build_object(
            'changed_count', (SELECT count(*) FROM restored)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        -- sector: custom rows removed; system rows restored as shipped
        -- (public.sector_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.sector WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.sector AS t
               SET name = fd.name, enabled = TRUE
              FROM public.sector_factory_default AS fd
             WHERE NOT t.custom AND t.path = fd.path
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.sector(path, name, enabled, custom)
            SELECT fd.path, fd.name, TRUE, FALSE
              FROM public.sector_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.sector AS t WHERE t.path = fd.path AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('sector', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope IN ('getting-started', 'customisation') THEN
        -- legal_form: custom rows removed; system rows restored as shipped
        -- (public.legal_form_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.legal_form WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.legal_form AS t
               SET name = fd.name, enabled = TRUE
              FROM public.legal_form_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.legal_form(code, name, enabled, custom)
            SELECT fd.code, fd.name, TRUE, FALSE
              FROM public.legal_form_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.legal_form AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('legal_form', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- ================================================================
    -- Scope: customisation: the /admin Customisation section restored to
    -- its factory defaults. Users are never touched.
    -- ================================================================

    CASE WHEN scope = 'customisation' THEN
        -- unit_size: custom rows removed; system rows restored as shipped
        -- (public.unit_size_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.unit_size WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.unit_size AS t
               SET name = fd.name, enabled = TRUE
              FROM public.unit_size_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.unit_size(code, name, enabled, custom)
            SELECT fd.code, fd.name, TRUE, FALSE
              FROM public.unit_size_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.unit_size AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('unit_size', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- data_source: custom rows removed; system rows restored as shipped
        -- (public.data_source_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.data_source WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.data_source AS t
               SET name = fd.name, enabled = TRUE
              FROM public.data_source_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.data_source(code, name, enabled, custom)
            SELECT fd.code, fd.name, TRUE, FALSE
              FROM public.data_source_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.data_source AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('data_source', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- foreign_participation: custom rows removed; system rows restored as shipped
        -- (public.foreign_participation_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.foreign_participation WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.foreign_participation AS t
               SET name = fd.name, enabled = TRUE
              FROM public.foreign_participation_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.foreign_participation(code, name, enabled, custom)
            SELECT fd.code, fd.name, TRUE, FALSE
              FROM public.foreign_participation_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.foreign_participation AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('foreign_participation', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- power_group_type: custom rows removed; system rows restored as shipped
        -- (public.power_group_type_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.power_group_type WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.power_group_type AS t
               SET name = fd.name, enabled = TRUE
              FROM public.power_group_type_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name)
            RETURNING 1
        ), added AS (
            INSERT INTO public.power_group_type(code, name, enabled, custom)
            SELECT fd.code, fd.name, TRUE, FALSE
              FROM public.power_group_type_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.power_group_type AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('power_group_type', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- legal_reorg_type: custom rows removed; system rows restored as shipped
        -- (public.legal_reorg_type_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.legal_reorg_type WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.legal_reorg_type AS t
               SET name = fd.name, description = fd.description, enabled = TRUE
              FROM public.legal_reorg_type_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name OR t.description IS DISTINCT FROM fd.description)
            RETURNING 1
        ), added AS (
            INSERT INTO public.legal_reorg_type(code, name, description, enabled, custom)
            SELECT fd.code, fd.name, fd.description, TRUE, FALSE
              FROM public.legal_reorg_type_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.legal_reorg_type AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('legal_reorg_type', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- legal_rel_type: custom rows removed; system rows restored as shipped
        -- (public.legal_rel_type_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.legal_rel_type WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.legal_rel_type AS t
               SET name = fd.name, description = fd.description, primary_influencer_only = fd.primary_influencer_only, enabled = TRUE
              FROM public.legal_rel_type_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name OR t.description IS DISTINCT FROM fd.description OR t.primary_influencer_only IS DISTINCT FROM fd.primary_influencer_only)
            RETURNING 1
        ), added AS (
            INSERT INTO public.legal_rel_type(code, name, description, primary_influencer_only, enabled, custom)
            SELECT fd.code, fd.name, fd.description, fd.primary_influencer_only, TRUE, FALSE
              FROM public.legal_rel_type_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.legal_rel_type AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('legal_rel_type', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- status: custom rows removed, system rows restored as shipped.
        WITH deleted AS (
            DELETE FROM public.status WHERE custom RETURNING 1
        ), restored AS (
            UPDATE public.status AS t
               SET name = fd.name, assigned_by_default = fd.assigned_by_default,
                   used_for_counting = fd.used_for_counting, priority = fd.priority, enabled = TRUE
              FROM public.status_factory_default AS fd
             WHERE NOT t.custom AND t.code = fd.code
               AND (NOT t.enabled OR t.name IS DISTINCT FROM fd.name
                    OR t.assigned_by_default IS DISTINCT FROM fd.assigned_by_default
                    OR t.used_for_counting IS DISTINCT FROM fd.used_for_counting
                    OR t.priority IS DISTINCT FROM fd.priority)
            RETURNING 1
        ), added AS (
            INSERT INTO public.status(code, name, assigned_by_default, used_for_counting, priority, enabled, custom)
            SELECT fd.code, fd.name, fd.assigned_by_default, fd.used_for_counting, fd.priority, TRUE, FALSE
              FROM public.status_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.status AS t WHERE t.code = fd.code AND NOT t.custom)
            RETURNING 1
        )
        SELECT jsonb_build_object('status', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        WITH deleted_tag AS (
            DELETE FROM public.tag WHERE custom RETURNING *
        ), changed_tag AS (
            UPDATE public.tag
               SET enabled = TRUE
             WHERE NOT custom
               AND NOT enabled
             RETURNING *
        )
        SELECT jsonb_build_object(
            'tag', jsonb_build_object(
                'deleted_count', (SELECT COUNT(*) FROM deleted_tag),
                'changed_count', (SELECT COUNT(*) FROM changed_tag)
            )
        ) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- stat_definition: rows not shipped removed; shipped rows restored as shipped
        -- (public.stat_definition_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.stat_definition AS t
             WHERE NOT EXISTS (SELECT 1 FROM public.stat_definition_factory_default AS fd WHERE fd.code = t.code)
            RETURNING 1
        ), restored AS (
            UPDATE public.stat_definition AS t
               SET type = fd.type, frequency = fd.frequency, name = fd.name, description = fd.description, priority = fd.priority, enabled = fd.enabled
              FROM public.stat_definition_factory_default AS fd
             WHERE t.code = fd.code AND (t.type IS DISTINCT FROM fd.type OR t.frequency IS DISTINCT FROM fd.frequency OR t.name IS DISTINCT FROM fd.name OR t.description IS DISTINCT FROM fd.description OR t.priority IS DISTINCT FROM fd.priority OR t.enabled IS DISTINCT FROM fd.enabled)
            RETURNING 1
        ), added AS (
            INSERT INTO public.stat_definition(code, type, frequency, name, description, priority, enabled)
            SELECT fd.code, fd.type, fd.frequency, fd.name, fd.description, fd.priority, fd.enabled
              FROM public.stat_definition_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.stat_definition AS t WHERE t.code = fd.code)
            RETURNING 1
        )
        SELECT jsonb_build_object('stat_definition', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    CASE WHEN scope = 'customisation' THEN
        -- external_ident_type: rows not shipped removed; shipped rows restored as shipped
        -- (public.external_ident_type_factory_default): edited ones updated, missing ones added.
        WITH deleted AS (
            DELETE FROM public.external_ident_type AS t
             WHERE NOT EXISTS (SELECT 1 FROM public.external_ident_type_factory_default AS fd WHERE fd.code = t.code)
            RETURNING 1
        ), restored AS (
            UPDATE public.external_ident_type AS t
               SET name = fd.name, description = fd.description, priority = fd.priority, enabled = fd.enabled
              FROM public.external_ident_type_factory_default AS fd
             WHERE t.code = fd.code AND (t.name IS DISTINCT FROM fd.name OR t.description IS DISTINCT FROM fd.description OR t.priority IS DISTINCT FROM fd.priority OR t.enabled IS DISTINCT FROM fd.enabled)
            RETURNING 1
        ), added AS (
            INSERT INTO public.external_ident_type(code, name, description, priority, enabled)
            SELECT fd.code, fd.name, fd.description, fd.priority, fd.enabled
              FROM public.external_ident_type_factory_default AS fd
             WHERE NOT EXISTS (SELECT 1 FROM public.external_ident_type AS t WHERE t.code = fd.code)
            RETURNING 1
        )
        SELECT jsonb_build_object('external_ident_type', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted),
            'changed_count', (SELECT count(*) FROM restored),
            'added_count', (SELECT count(*) FROM added)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    -- public.activity_category_standard rows are never deleted: they are the
    -- system's standards, restored above to their factory defaults.

    RETURN result;
END;
$function$
;

CREATE OR REPLACE FUNCTION admin.apply_rls_to_all_tables()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- To list all tables in public schema, run in psql:
    -- SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
    --
    -- ########### add_rls_regular_user_can_read ###########
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.region'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.sector'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_form'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_standard'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.settings'::regclass);
    -- We don't need to apply the standard RLS function to activity_category_access
    -- as it has custom policies that only allow admin_user to modify it
    -- PERFORM admin.add_rls_regular_user_can_read('public.activity_category_access'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.country'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.data_source'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.tag'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.unit_size'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.power_group_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_reorg_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_rel_type'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.foreign_participation'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.status'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.external_ident_type'::regclass);

    PERFORM admin.add_rls_regular_user_can_read('public.person_role'::regclass);
    -- We don't need to apply the standard RLS function to region_access
    -- as it has custom policies that only allow admin_user to modify it
    -- PERFORM admin.add_rls_regular_user_can_read('public.region_access'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.stat_definition'::regclass);
    -- Is updated by the statbus worker, using authorized functions.
    PERFORM admin.add_rls_regular_user_can_read('public.timepoints'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timesegments'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timesegments_years'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_establishment'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.timeline_enterprise'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.activity_category_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.region_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.sector_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.data_source_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.legal_form_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.country_used'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_unit_facet'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history_facet_delta'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.statistical_history_period'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_establishment_activity_differs'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_establishments_above_legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_legal_unit_above_establishments'::regclass);
    --
    -- ########### add_rls_regular_user_can_edit ###########
    PERFORM admin.add_rls_regular_user_can_edit('public.image'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.establishment'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.legal_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.enterprise'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.power_group'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.power_root'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.external_ident'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.activity'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.contact'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.unit_notes'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.tag_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.stat_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person_for_unit'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.person'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.location'::regclass);
    PERFORM admin.add_rls_regular_user_can_edit('public.legal_relationship'::regclass);
    --
END;
$function$
;

DROP FUNCTION public.statistical_unit_quality(public.quality_rule, date, integer);
DROP FUNCTION public.quality_finding_derive();
DROP VIEW public.quality_finding_def;
DROP TABLE public.quality_finding;
DROP VIEW public.quality_check;
DROP TABLE public.quality_check_switched_off;
DROP FUNCTION public.quality_rule_per_stat(public.quality_rule);
DROP TYPE public.quality_rule;

-- The restored tables are filled by the next worker.derive_quality; queue one (none on an empty database).
INSERT INTO worker.tasks (command, payload)
SELECT 'derive_quality', jsonb_build_object('command', 'derive_quality', 'valid_from', '-infinity', 'valid_until', 'infinity')
WHERE EXISTS (SELECT 1 FROM public.statistical_unit);
-- A queued task waits until the worker is told (as worker.enqueue_derive_statistical_unit_all does).
SELECT pg_notify('worker_tasks', 'analytics');

END;
