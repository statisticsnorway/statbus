```sql
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_hash_partition int4range := (payload->>'hash_partition')::int4range;
    -- Pre-compute explicit half-open bounds so the btree index on hash_slot is
    -- used. Range containment (<@) via a variable int4range is not planned as a
    -- btree scan at 2.2M rows; explicit bounds are. Mirrors the sibling
    -- derive_statistical_history_facet_period which passes scalar bounds.
    v_from  integer := lower(v_hash_partition);
    v_until integer := upper(v_hash_partition);
    v_record_changes boolean := COALESCE((payload->>'record_changes')::boolean, false);
    v_row_count bigint;
BEGIN
    -- The slice as it was, so the combinations this rewrite changes, including
    -- the removed ones, can be recorded for the scoped reduce.
    IF v_record_changes THEN
        IF to_regclass('pg_temp._unit_facet_slice_before') IS NOT NULL THEN DROP TABLE _unit_facet_slice_before; END IF;
        CREATE TEMP TABLE _unit_facet_slice_before ON COMMIT DROP AS
        SELECT * FROM public.statistical_unit_facet_staging
         WHERE hash_slot >= v_from AND hash_slot < v_until;
    END IF;

    DELETE FROM public.statistical_unit_facet_staging
     WHERE hash_slot >= v_from AND hash_slot < v_until;

    -- STATBUS-475: aggregate by the unit's EXISTENCE window within each record
    -- (canonical rule, STATBUS-460), not by the record window, so the
    -- drilldown's valid_from <= valid_on < valid_until counts existing units.
    INSERT INTO public.statistical_unit_facet_staging
    SELECT su.hash_slot,
           e.existence_from, e.existence_until - 1, e.existence_until, su.unit_type,
           su.physical_region_path, su.primary_activity_category_path,
           su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id,
           COUNT(*)::integer,
           public.jsonb_stats_merge_agg(su.stats_summary)
    FROM public.statistical_unit AS su
    CROSS JOIN LATERAL (
        SELECT public.unit_existence_from(su.valid_from, su.birth_date) AS existence_from,
               public.unit_existence_until(su.valid_until, su.death_date) AS existence_until
    ) AS e
    WHERE su.used_for_counting
      AND su.hash_slot >= v_from AND su.hash_slot < v_until
      AND e.existence_from < e.existence_until
    GROUP BY su.hash_slot, e.existence_from, e.existence_until, su.unit_type,
             su.physical_region_path, su.primary_activity_category_path,
             su.sector_path, su.legal_form_id, su.physical_country_id, su.status_id;
    GET DIAGNOSTICS v_row_count := ROW_COUNT;

    -- A combination changed when any of its rows in the slice was added,
    -- altered or removed: the symmetric difference of before and after.
    -- Inserted in key order, so concurrent children wait on each other's
    -- uncommitted keys in the same order and cannot deadlock.
    IF v_record_changes THEN
        INSERT INTO worker.statistical_unit_facet_changed
        SELECT DISTINCT d.valid_from, d.valid_to, d.valid_until, d.unit_type,
               d.physical_region_path, d.primary_activity_category_path,
               d.sector_path, d.legal_form_id, d.physical_country_id, d.status_id
        FROM (
            (SELECT * FROM _unit_facet_slice_before
             EXCEPT ALL
             SELECT * FROM public.statistical_unit_facet_staging
              WHERE hash_slot >= v_from AND hash_slot < v_until)
            UNION ALL
            (SELECT * FROM public.statistical_unit_facet_staging
              WHERE hash_slot >= v_from AND hash_slot < v_until
             EXCEPT ALL
             SELECT * FROM _unit_facet_slice_before)
        ) AS d
        ORDER BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
        ON CONFLICT DO NOTHING;
    END IF;

    p_info := jsonb_build_object('rows_inserted', v_row_count);
END;
$procedure$
```
