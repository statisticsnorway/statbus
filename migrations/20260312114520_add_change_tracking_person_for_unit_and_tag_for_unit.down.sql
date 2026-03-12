BEGIN;

-- Drop change-tracking triggers from person_for_unit
DROP TRIGGER IF EXISTS a_person_for_unit_log_insert ON public.person_for_unit;
DROP TRIGGER IF EXISTS a_person_for_unit_log_update ON public.person_for_unit;
DROP TRIGGER IF EXISTS a_person_for_unit_log_delete ON public.person_for_unit;
DROP TRIGGER IF EXISTS b_person_for_unit_ensure_collect ON public.person_for_unit;

-- Drop change-tracking triggers from tag_for_unit
DROP TRIGGER IF EXISTS a_tag_for_unit_log_insert ON public.tag_for_unit;
DROP TRIGGER IF EXISTS a_tag_for_unit_log_update ON public.tag_for_unit;
DROP TRIGGER IF EXISTS a_tag_for_unit_log_delete ON public.tag_for_unit;
DROP TRIGGER IF EXISTS b_tag_for_unit_ensure_collect ON public.tag_for_unit;

-- Restore original log_base_change without person_for_unit and tag_for_unit branches
CREATE OR REPLACE FUNCTION worker.log_base_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $log_base_change$
DECLARE
    v_columns TEXT;
    v_has_valid_range BOOLEAN;
    v_where_clause TEXT := '';
    v_source TEXT;
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_ent_ids int4multirange;
    v_pg_ids int4multirange;
    v_valid_range datemultirange;
BEGIN
    CASE TG_TABLE_NAME
        WHEN 'establishment' THEN
            v_columns := 'id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'legal_unit' THEN
            v_columns := 'NULL::INT AS est_id, id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'enterprise' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'external_ident' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'legal_relationship' THEN
            -- LR changes only affect power groups, not individual LUs/enterprises.
            -- Only log when derived_power_group_id is assigned (NULL = PG not yet linked).
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, derived_power_group_id AS pg_id';
            v_has_valid_range := TRUE;

            v_where_clause := ' WHERE derived_power_group_id IS NOT NULL';
        WHEN 'power_group' THEN
            -- PG metadata changes (name, type_id, etc.) affect PG statistical units.
            -- Timeless table — no valid_range.
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, id AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'power_root' THEN
            -- PR changes (NSO custom_root override) affect the power group's timeline.
            -- Temporal table — has valid_range.
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, power_group_id AS pg_id';
            v_has_valid_range := TRUE;
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported table %', TG_TABLE_NAME;
    END CASE;

    IF v_has_valid_range THEN
        v_columns := v_columns || ', valid_range';
    ELSE
        v_columns := v_columns || ', NULL::daterange AS valid_range';
    END IF;

    CASE TG_OP
        WHEN 'INSERT' THEN v_source := format('SELECT %s FROM new_rows%s', v_columns, v_where_clause);
        WHEN 'DELETE' THEN v_source := format('SELECT %s FROM old_rows%s', v_columns, v_where_clause);
        WHEN 'UPDATE' THEN v_source := format('SELECT %s FROM old_rows%s UNION ALL SELECT %s FROM new_rows%s', v_columns, v_where_clause, v_columns, v_where_clause);
        ELSE RAISE EXCEPTION 'log_base_change: unsupported operation %', TG_OP;
    END CASE;

    -- No UNION ALL for influenced_id — LR changes only log PG IDs, not individual LU IDs

    EXECUTE format(
        'SELECT COALESCE(range_agg(int4range(est_id, est_id, %1$L)) FILTER (WHERE est_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(lu_id, lu_id, %1$L)) FILTER (WHERE lu_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(ent_id, ent_id, %1$L)) FILTER (WHERE ent_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(pg_id, pg_id, %1$L)) FILTER (WHERE pg_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(valid_range) FILTER (WHERE valid_range IS NOT NULL), %3$L::datemultirange)
         FROM (%s) AS mapped',
        '[]', '{}', '{}', v_source
    ) INTO v_est_ids, v_lu_ids, v_ent_ids, v_pg_ids, v_valid_range;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, valid_ranges)
        VALUES (v_est_ids, v_lu_ids, v_ent_ids, v_pg_ids, v_valid_range);
    END IF;

    RETURN NULL;
END;
$log_base_change$;

END;
