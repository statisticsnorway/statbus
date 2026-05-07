-- Migration 20260507161037: extend highcharts with stats paths
--
-- Replace public.statistical_history_highcharts to:
--  1. Accept dotted paths into stats_summary as series codes
--     (e.g. 'stats_summary.turnover.sum', 'stats_summary.is_active.counts.true').
--     The path mirrors the literal JSONB structure and is also the #> extraction array.
--  2. Reject partial paths with a fail-fast EXCEPTION carrying a HINT listing the
--     available next-level codes.
--  3. Remove the redundant top-level stats_summary blob from the response — anything
--     a caller wants from it is now requested explicitly as one or more path entries
--     in p_series_codes and returned per-period as a regular [ts, num] series.
--
-- Design and rationale: see plan
-- improve-statistical-history-highcharts-b-synchronous-clover.md

BEGIN;

CREATE OR REPLACE FUNCTION public.statistical_history_highcharts(p_resolution history_resolution, p_unit_type statistical_unit_type, p_year integer DEFAULT NULL::integer, p_series_codes text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $statistical_history_highcharts$
DECLARE
    result            jsonb;
    v_filtered_codes  text[];
    v_static_codes    text[] := ARRAY[]::text[];
    v_merged_summary  jsonb;
    v_req_code        text;
    v_path            text[];
    v_node            jsonb;
    v_msgs            text[] := ARRAY[]::text[];
    v_hints           text[] := ARRAY[]::text[];
BEGIN
    -- Static catalog: 18 historical-change codes plus a single bootstrap entry for the
    -- top-level 'stats_summary' partial. The bootstrap is advertised in `available_series`
    -- so callers can discover that more paths exist beyond the static set; it is itself
    -- never emitted as a series (resolution treats it as a partial and raises an error).
    IF to_regclass('pg_temp.series_definition') IS NOT NULL THEN DROP TABLE series_definition; END IF;
    CREATE TEMP TABLE series_definition(priority int, is_default boolean, code text PRIMARY KEY, name text) ON COMMIT DROP;
    INSERT INTO series_definition(priority, is_default, code, name)
    VALUES
        (10,  true,  'countable_count',                          'Unit Count'),
        (11,  false, 'countable_change',                         'Unit Count Change'),
        (12,  false, 'countable_added_count',                    'Units Added (Countable)'),
        (13,  false, 'countable_removed_count',                  'Units Removed (Countable)'),
        (14,  false, 'exists_count',                             'Existing Units'),
        (15,  false, 'exists_change',                            'Existing Units Change'),
        (16,  false, 'exists_added_count',                       'Units Added (Existence)'),
        (17,  false, 'exists_removed_count',                     'Units Removed (Existence)'),
        (20,  true , 'births',                                   'Births'),
        (30,  true , 'deaths',                                   'Deaths'),
        (40,  false, 'name_change_count',                        'Name Changes'),
        (50,  true , 'primary_activity_category_change_count',   'Primary Activity Changes'),
        (60,  false, 'secondary_activity_category_change_count', 'Secondary Activity Changes'),
        (70,  false, 'sector_change_count',                      'Sector Changes'),
        (80,  false, 'legal_form_change_count',                  'Legal Form Changes'),
        (90,  true , 'physical_region_change_count',             'Region Changes'),
        (100, false, 'physical_country_change_count',            'Country Changes'),
        (110, false, 'physical_address_change_count',            'Physical Address Changes'),
        (200, false, 'stats_summary',                            'Statistics Summary');

    -- Holds (code, jsonb_path) for every requested stats path that resolved to a numeric leaf.
    -- IDENTITY column preserves the caller-supplied order in the response.
    IF to_regclass('pg_temp.stats_path_buffer') IS NOT NULL THEN DROP TABLE stats_path_buffer; END IF;
    CREATE TEMP TABLE stats_path_buffer(
        ord        int GENERATED ALWAYS AS IDENTITY,
        code       text PRIMARY KEY,
        jsonb_path text[]
    ) ON COMMIT DROP;

    -- Compute the merged stats_summary once. It is the per-call catalog for stats paths
    -- (interrogated directly by `#>`) and the source for partial-path HINT children.
    SELECT COALESCE(public.jsonb_stats_merge_agg(sh.stats_summary), '{}'::jsonb)
    INTO v_merged_summary
    FROM public.statistical_history sh
    WHERE sh.resolution = p_resolution
      AND sh.unit_type  = p_unit_type
      AND (p_year IS NULL OR sh.year = p_year);

    -- Resolve each requested code in caller-supplied order.
    IF p_series_codes IS NOT NULL AND cardinality(p_series_codes) > 0 THEN
        FOREACH v_req_code IN ARRAY p_series_codes LOOP
            IF EXISTS (SELECT 1 FROM series_definition sd WHERE sd.code = v_req_code AND sd.code <> 'stats_summary') THEN
                -- Static code: extracted from a fixed column of public.statistical_history.
                v_static_codes := v_static_codes || v_req_code;

            ELSIF v_req_code = 'stats_summary' OR v_req_code LIKE 'stats_summary.%' THEN
                v_path := CASE
                    WHEN v_req_code = 'stats_summary'
                        THEN ARRAY[]::text[]
                    ELSE string_to_array(substr(v_req_code, length('stats_summary.') + 1), '.')
                END;

                IF 'type' = ANY(v_path) THEN
                    -- Bookkeeping segments are not addressable.
                    v_msgs := v_msgs || format('Unknown series code "%s"', v_req_code);
                    CONTINUE;
                END IF;

                v_node := v_merged_summary #> v_path;

                CASE jsonb_typeof(v_node)
                    WHEN 'number' THEN
                        INSERT INTO stats_path_buffer(code, jsonb_path) VALUES (v_req_code, v_path)
                        ON CONFLICT (code) DO NOTHING;  -- caller may pass a duplicate; first wins
                    WHEN 'object' THEN
                        v_msgs := v_msgs || format('Series code "%s" is incomplete; pick a leaf', v_req_code);
                        v_hints := v_hints || COALESCE(
                            (SELECT 'Try one of: ' || string_agg(format('%s.%s', v_req_code, k), ', ' ORDER BY k)
                               FROM jsonb_object_keys(v_node) AS k
                              WHERE k <> 'type'),
                            format('No completions available under "%s"', v_req_code)
                        );
                    ELSE
                        v_msgs := v_msgs || format('Unknown series code "%s"', v_req_code);
                END CASE;

            ELSE
                v_msgs := v_msgs || format('Unknown series code "%s"', v_req_code);
            END IF;
        END LOOP;

        IF cardinality(v_msgs) > 0 THEN
            DECLARE
                v_hint_text text := NULLIF(array_to_string(v_hints, E'\n'), '');
            BEGIN
                -- USING HINT = NULL is rejected by PG; emit a HINT-less RAISE in that case.
                IF v_hint_text IS NOT NULL THEN
                    RAISE EXCEPTION '%', array_to_string(v_msgs, '; ') USING HINT = v_hint_text;
                ELSE
                    RAISE EXCEPTION '%', array_to_string(v_msgs, '; ');
                END IF;
            END;
        END IF;
    END IF;

    -- Default-on selection: when caller passed nothing, fall back to is_default static codes.
    IF p_series_codes IS NULL OR cardinality(p_series_codes) = 0 THEN
        v_static_codes := COALESCE((SELECT array_agg(code ORDER BY priority) FROM series_definition WHERE is_default), ARRAY[]::text[]);
    END IF;

    v_filtered_codes := v_static_codes
                     || COALESCE((SELECT array_agg(code ORDER BY ord) FROM stats_path_buffer), ARRAY[]::text[]);

    WITH base AS (
        -- Highcharts expects UTC milliseconds since epoch.
        SELECT
            extract(epoch FROM
                CASE p_resolution
                    WHEN 'year'       THEN make_timestamp(year, 1, 1, 0, 0, 0)
                    WHEN 'year-month' THEN make_timestamp(year, month, 1, 0, 0, 0)
                END
            )::bigint * 1000 AS ts_epoch_ms,
            exists_count, exists_change, exists_added_count, exists_removed_count,
            countable_count, countable_change, countable_added_count, countable_removed_count,
            births, deaths, name_change_count,
            primary_activity_category_change_count, secondary_activity_category_change_count,
            sector_change_count, legal_form_change_count, physical_region_change_count,
            physical_country_change_count, physical_address_change_count,
            stats_summary
        FROM public.statistical_history
        WHERE resolution = p_resolution
          AND unit_type  = p_unit_type
          AND (p_year IS NULL OR year = p_year)
    ),
    static_pairs AS (
                  SELECT 'countable_count'                          AS code, jsonb_build_array(ts_epoch_ms, countable_count)                          AS pair, ts_epoch_ms FROM base WHERE 'countable_count'                          = ANY(v_static_codes)
        UNION ALL SELECT 'countable_change',                                 jsonb_build_array(ts_epoch_ms, countable_change),                                 ts_epoch_ms FROM base WHERE 'countable_change'                         = ANY(v_static_codes)
        UNION ALL SELECT 'countable_added_count',                            jsonb_build_array(ts_epoch_ms, countable_added_count),                            ts_epoch_ms FROM base WHERE 'countable_added_count'                    = ANY(v_static_codes)
        UNION ALL SELECT 'countable_removed_count',                          jsonb_build_array(ts_epoch_ms, countable_removed_count),                          ts_epoch_ms FROM base WHERE 'countable_removed_count'                  = ANY(v_static_codes)
        UNION ALL SELECT 'exists_count',                                     jsonb_build_array(ts_epoch_ms, exists_count),                                     ts_epoch_ms FROM base WHERE 'exists_count'                             = ANY(v_static_codes)
        UNION ALL SELECT 'exists_change',                                    jsonb_build_array(ts_epoch_ms, exists_change),                                    ts_epoch_ms FROM base WHERE 'exists_change'                            = ANY(v_static_codes)
        UNION ALL SELECT 'exists_added_count',                               jsonb_build_array(ts_epoch_ms, exists_added_count),                               ts_epoch_ms FROM base WHERE 'exists_added_count'                       = ANY(v_static_codes)
        UNION ALL SELECT 'exists_removed_count',                             jsonb_build_array(ts_epoch_ms, exists_removed_count),                             ts_epoch_ms FROM base WHERE 'exists_removed_count'                     = ANY(v_static_codes)
        UNION ALL SELECT 'births',                                           jsonb_build_array(ts_epoch_ms, births),                                           ts_epoch_ms FROM base WHERE 'births'                                   = ANY(v_static_codes)
        UNION ALL SELECT 'deaths',                                           jsonb_build_array(ts_epoch_ms, deaths),                                           ts_epoch_ms FROM base WHERE 'deaths'                                   = ANY(v_static_codes)
        UNION ALL SELECT 'name_change_count',                                jsonb_build_array(ts_epoch_ms, name_change_count),                                ts_epoch_ms FROM base WHERE 'name_change_count'                        = ANY(v_static_codes)
        UNION ALL SELECT 'primary_activity_category_change_count',           jsonb_build_array(ts_epoch_ms, primary_activity_category_change_count),           ts_epoch_ms FROM base WHERE 'primary_activity_category_change_count'   = ANY(v_static_codes)
        UNION ALL SELECT 'secondary_activity_category_change_count',         jsonb_build_array(ts_epoch_ms, secondary_activity_category_change_count),         ts_epoch_ms FROM base WHERE 'secondary_activity_category_change_count' = ANY(v_static_codes)
        UNION ALL SELECT 'sector_change_count',                              jsonb_build_array(ts_epoch_ms, sector_change_count),                              ts_epoch_ms FROM base WHERE 'sector_change_count'                      = ANY(v_static_codes)
        UNION ALL SELECT 'legal_form_change_count',                          jsonb_build_array(ts_epoch_ms, legal_form_change_count),                          ts_epoch_ms FROM base WHERE 'legal_form_change_count'                  = ANY(v_static_codes)
        UNION ALL SELECT 'physical_region_change_count',                     jsonb_build_array(ts_epoch_ms, physical_region_change_count),                     ts_epoch_ms FROM base WHERE 'physical_region_change_count'             = ANY(v_static_codes)
        UNION ALL SELECT 'physical_country_change_count',                    jsonb_build_array(ts_epoch_ms, physical_country_change_count),                    ts_epoch_ms FROM base WHERE 'physical_country_change_count'            = ANY(v_static_codes)
        UNION ALL SELECT 'physical_address_change_count',                    jsonb_build_array(ts_epoch_ms, physical_address_change_count),                    ts_epoch_ms FROM base WHERE 'physical_address_change_count'            = ANY(v_static_codes)
    ),
    stats_pairs AS (
        SELECT
            spb.code,
            jsonb_build_array(b.ts_epoch_ms, ((b.stats_summary #> spb.jsonb_path)::text)::numeric) AS pair,
            b.ts_epoch_ms
        FROM base AS b CROSS JOIN stats_path_buffer AS spb
    ),
    series_data_map AS (
        SELECT code, jsonb_agg(pair ORDER BY ts_epoch_ms) AS data
        FROM (
                      SELECT code, pair, ts_epoch_ms FROM static_pairs
            UNION ALL SELECT code, pair, ts_epoch_ms FROM stats_pairs
        ) AS u
        GROUP BY code
    ),
    -- Friendly stat-leaf labels per plan §2c: stat_definition.name (or initcap fallback)
    -- for the stat code, then a single space, then the last segment with _-to-space and
    -- only the first letter uppercased. The 'counts' indirection is implicitly skipped
    -- because we only render seg1 + segN.
    stats_names AS (
        SELECT
            spb.ord,
            spb.code,
            COALESCE(sdf.name, initcap(replace(spb.jsonb_path[1], '_', ' ')))
            || ' '
            || (
                SELECT upper(substr(s, 1, 1)) || substr(s, 2)
                FROM (SELECT replace(spb.jsonb_path[cardinality(spb.jsonb_path)], '_', ' ') AS s) AS x
            ) AS name
        FROM stats_path_buffer AS spb
        LEFT JOIN public.stat_definition AS sdf ON sdf.enabled AND sdf.code = spb.jsonb_path[1]
    )
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'resolution',       p_resolution,
        'unit_type',        p_unit_type,
        'year',             p_year,
        -- available_series is a discoverability hint: only include it when the caller
        -- gave no codes (i.e. they're in "what can I ask for?" mode). Once they specify
        -- a series_codes array they've decided what they want and the field is noise.
        'available_series', CASE
            WHEN p_series_codes IS NULL OR cardinality(p_series_codes) = 0 THEN
                (
                    SELECT jsonb_agg(jsonb_build_object('code', code, 'name', name, 'priority', priority) ORDER BY priority)
                    FROM series_definition
                    WHERE code <> ALL(v_filtered_codes)
                )
            ELSE NULL  -- jsonb_strip_nulls drops the key
        END,
        'filtered_series',  to_jsonb(v_filtered_codes),
        'series', (
            SELECT jsonb_agg(entry ORDER BY ord)
            FROM (
                -- Static codes preserve their priority ordering.
                SELECT sd.priority AS ord,
                       jsonb_build_object('code', sd.code, 'name', sd.name,
                                          'data', COALESCE(sdm.data, '[]'::jsonb)) AS entry
                FROM series_definition AS sd
                LEFT JOIN series_data_map AS sdm ON sdm.code = sd.code
                WHERE sd.code = ANY(v_static_codes)
                UNION ALL
                -- Stats codes appended after the static block, in caller-supplied order.
                SELECT 1000 + sn.ord AS ord,
                       jsonb_build_object('code', sn.code, 'name', sn.name,
                                          'data', COALESCE(sdm.data, '[]'::jsonb)) AS entry
                FROM stats_names AS sn
                LEFT JOIN series_data_map AS sdm ON sdm.code = sn.code
            ) AS ordered
        )
    )) INTO result;

    RETURN result;
END;
$statistical_history_highcharts$;

END;
