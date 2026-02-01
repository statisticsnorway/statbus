-- Down Migration: Remove closed group batching, restore original derive_statistical_unit
BEGIN;

-- ============================================================================
-- Remove command and queue registration
-- ============================================================================
DELETE FROM worker.command_registry 
WHERE command = 'statistical_unit_refresh_batch';

DELETE FROM worker.queue_registry 
WHERE queue = 'analytics_batch';

-- Remove concurrency column from queue_registry
ALTER TABLE worker.queue_registry 
DROP COLUMN IF EXISTS default_concurrency;


-- ============================================================================
-- Drop new objects
-- ============================================================================
DROP PROCEDURE IF EXISTS worker.statistical_unit_refresh_batch(JSONB);
DROP FUNCTION IF EXISTS worker.enqueue_statistical_unit_refresh_batch(INT, INT[], INT[], INT[], DATE, DATE, BOOLEAN);
DROP FUNCTION IF EXISTS public.get_closed_group_batches(INT, INT[], INT[], INT[]);
DROP FUNCTION IF EXISTS public.get_enterprise_closed_groups();
DROP PROCEDURE IF EXISTS public.timesegments_years_refresh_concurrent();


-- ============================================================================
-- Restore original derive_statistical_unit function
-- ============================================================================
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
  p_establishment_id_ranges int4multirange DEFAULT NULL,
  p_legal_unit_id_ranges int4multirange DEFAULT NULL,
  p_enterprise_id_ranges int4multirange DEFAULT NULL,
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $derive_statistical_unit$
DECLARE
    v_all_establishment_ids int[];
    v_all_legal_unit_ids int[];
    v_all_enterprise_ids int[];
BEGIN
    IF p_establishment_id_ranges IS NULL AND p_legal_unit_id_ranges IS NULL AND p_enterprise_id_ranges IS NULL THEN
        -- Full refresh
        CALL public.timepoints_refresh();
        CALL public.timesegments_refresh();
        CALL public.timesegments_years_refresh();
        CALL public.timeline_establishment_refresh();
        CALL public.timeline_legal_unit_refresh();
        CALL public.timeline_enterprise_refresh();
        CALL public.statistical_unit_refresh();
    ELSE
        -- Partial Refresh Logic
        DECLARE
            initial_es_ids INT[] := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r));
            initial_lu_ids INT[] := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_legal_unit_id_ranges,    '{}'::int4multirange)) AS t(r));
            initial_en_ids INT[] := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_enterprise_id_ranges,    '{}'::int4multirange)) AS t(r));
        BEGIN
            WITH RECURSIVE all_affected_units(id, type) AS (
                (
                    SELECT id, 'establishment'::public.statistical_unit_type AS type FROM unnest(initial_es_ids) AS t(id)
                    UNION ALL
                    SELECT id, 'legal_unit' FROM unnest(initial_lu_ids) AS t(id)
                    UNION ALL
                    SELECT id, 'enterprise' FROM unnest(initial_en_ids) AS t(id)
                )
                UNION
                SELECT related.id, related.type
                FROM all_affected_units a
                JOIN LATERAL (
                    SELECT es.legal_unit_id AS id, 'legal_unit'::public.statistical_unit_type AS type FROM public.establishment es WHERE a.type = 'establishment' AND a.id = es.id AND es.legal_unit_id IS NOT NULL
                    UNION ALL
                    SELECT es.enterprise_id, 'enterprise' FROM public.establishment es WHERE a.type = 'establishment' AND a.id = es.id AND es.enterprise_id IS NOT NULL
                    UNION ALL
                    SELECT lu.enterprise_id, 'enterprise' FROM public.legal_unit lu WHERE a.type = 'legal_unit' AND a.id = lu.id AND lu.enterprise_id IS NOT NULL
                    UNION ALL
                    SELECT lu.id, 'legal_unit' FROM public.legal_unit lu WHERE a.type = 'enterprise' AND a.id = lu.enterprise_id
                    UNION ALL
                    SELECT es.id, 'establishment' FROM public.establishment es WHERE a.type = 'enterprise' AND a.id = es.enterprise_id
                    UNION ALL
                    SELECT es.id, 'establishment' FROM public.establishment es WHERE a.type = 'legal_unit' AND a.id = es.legal_unit_id
                ) AS related ON true
            )
            SELECT
                array_agg(id) FILTER (WHERE type = 'establishment'),
                array_agg(id) FILTER (WHERE type = 'legal_unit'),
                array_agg(id) FILTER (WHERE type = 'enterprise')
            INTO
                v_all_establishment_ids,
                v_all_legal_unit_ids,
                v_all_enterprise_ids
            FROM all_affected_units;

            v_all_establishment_ids := array_cat(v_all_establishment_ids, COALESCE((SELECT array_agg(DISTINCT unnest) FROM (SELECT unnest(related_establishment_ids) FROM public.statistical_unit WHERE related_establishment_ids && v_all_establishment_ids) x), '{}'));
            v_all_legal_unit_ids := array_cat(v_all_legal_unit_ids, COALESCE((SELECT array_agg(DISTINCT unnest) FROM (SELECT unnest(related_legal_unit_ids) FROM public.statistical_unit WHERE related_legal_unit_ids && v_all_legal_unit_ids) x), '{}'));
            v_all_enterprise_ids := array_cat(v_all_enterprise_ids, COALESCE((SELECT array_agg(DISTINCT unnest) FROM (SELECT unnest(related_enterprise_ids) FROM public.statistical_unit WHERE related_enterprise_ids && v_all_enterprise_ids) x), '{}'));

            v_all_establishment_ids := ARRAY(SELECT DISTINCT e FROM unnest(v_all_establishment_ids) e WHERE e IS NOT NULL);
            v_all_legal_unit_ids    := ARRAY(SELECT DISTINCT l FROM unnest(v_all_legal_unit_ids) l WHERE l IS NOT NULL);
            v_all_enterprise_ids    := ARRAY(SELECT DISTINCT en FROM unnest(v_all_enterprise_ids) en WHERE en IS NOT NULL);
        END;

        CALL public.timepoints_refresh(
            p_establishment_id_ranges => public.array_to_int4multirange(v_all_establishment_ids),
            p_legal_unit_id_ranges => public.array_to_int4multirange(v_all_legal_unit_ids),
            p_enterprise_id_ranges => public.array_to_int4multirange(v_all_enterprise_ids)
        );

        CALL public.timesegments_refresh(
            p_establishment_id_ranges => public.array_to_int4multirange(v_all_establishment_ids),
            p_legal_unit_id_ranges => public.array_to_int4multirange(v_all_legal_unit_ids),
            p_enterprise_id_ranges => public.array_to_int4multirange(v_all_enterprise_ids)
        );

        CALL public.timesegments_years_refresh();

        CALL public.timeline_establishment_refresh(p_unit_id_ranges => public.array_to_int4multirange(v_all_establishment_ids));
        CALL public.timeline_legal_unit_refresh(p_unit_id_ranges => public.array_to_int4multirange(v_all_legal_unit_ids));
        CALL public.timeline_enterprise_refresh(p_unit_id_ranges => public.array_to_int4multirange(v_all_enterprise_ids));

        CALL public.statistical_unit_refresh(
            p_establishment_id_ranges => public.array_to_int4multirange(v_all_establishment_ids),
            p_legal_unit_id_ranges => public.array_to_int4multirange(v_all_legal_unit_ids),
            p_enterprise_id_ranges => public.array_to_int4multirange(v_all_enterprise_ids)
        );
    END IF;

    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    PERFORM worker.enqueue_derive_reports(
        p_valid_from => derive_statistical_unit.p_valid_from,
        p_valid_until => derive_statistical_unit.p_valid_until
    );
END;
$derive_statistical_unit$;

END;
