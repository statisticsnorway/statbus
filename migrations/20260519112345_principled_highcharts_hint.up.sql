-- Migration 20260519112345: principled_highcharts_hint
--
-- Replace data-derived HINT/completion enumeration in
-- `public.statistical_history_highcharts` with a SCHEMA-derived catalog built
-- at function entry from `public.stat_definition` × the canonical leaf shape
-- of `jsonb_stats_agg` per stat type.
--
-- Three behavioural changes:
--   §A  Normalise `stats_summary.` and `stats_summary..turnover` style inputs by
--       collapsing trailing dots and repeated internal dot runs before path parse.
--   §B  When a `stats_summary.<known_stat>[.bogus]` path resolves to nothing on
--       real data, emit HINT listing the valid leaves of `<known_stat>` from the
--       catalog. When `<stat>` itself is unknown, fall back to listing valid
--       top-level stat paths from the catalog.
--   §C  Unknown top-level series codes (typos like `jsonb_stats`) emit HINT
--       listing the full union of static series_definition codes and
--       `stats_summary.<stat_code>` paths from the catalog.
--
-- Data lookup (the numeric values returned in `series`) still uses real
-- `public.statistical_history.stats_summary` — only HINT enumeration changes.
BEGIN;

CREATE OR REPLACE FUNCTION public.statistical_history_highcharts(p_resolution history_resolution, p_unit_type statistical_unit_type, p_year integer DEFAULT NULL::integer, p_series_codes text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    result            jsonb;
    v_filtered_codes  text[];
    v_static_codes    text[] := ARRAY[]::text[];
    v_merged_summary  jsonb;
    -- Schema-derived completion catalog. Built once per call from
    -- `public.stat_definition` × `jsonb_stats_to_agg(jsonb_stats_agg(code, stat(synthetic)))`.
    -- Drives HINT enumeration in the partial-path / bogus-leaf / typo branches;
    -- independent of whether any `statistical_history` rows exist.
    v_catalog_summary jsonb  := '{}'::jsonb;
    v_sd              record;
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

    -- Compute the merged stats_summary once. Used for ACCEPTANCE (jsonb_typeof check) and
    -- for the actual numeric data extraction in the `series` payload.
    SELECT COALESCE(public.jsonb_stats_merge_agg(sh.stats_summary), '{}'::jsonb)
    INTO v_merged_summary
    FROM public.statistical_history sh
    WHERE sh.resolution = p_resolution
      AND sh.unit_type  = p_unit_type
      AND (p_year IS NULL OR sh.year = p_year);

    -- Build v_catalog_summary from schema. One synthetic-value pass per enabled stat
    -- yields the canonical leaf-bearing shape that `jsonb_stats_merge_agg` would
    -- produce over real data. Per-call cost is negligible (stat_definition is tiny).
    -- Polymorphism note: `stat()` is anyelement — a single CASE expression with
    -- different-typed branches won't compile. PL/pgSQL IF/ELSIF per type sidesteps it.
    FOR v_sd IN SELECT sd.code, sd.type::text AS type_text
                FROM public.stat_definition AS sd
                WHERE sd.enabled
                ORDER BY sd.code
    LOOP
        IF v_sd.type_text = 'int' THEN
            v_catalog_summary := v_catalog_summary || jsonb_build_object(
                v_sd.code,
                (public.jsonb_stats_to_agg(public.jsonb_stats_agg(v_sd.code, public.stat(0))) -> v_sd.code)
            );
        ELSIF v_sd.type_text = 'float' THEN
            v_catalog_summary := v_catalog_summary || jsonb_build_object(
                v_sd.code,
                (public.jsonb_stats_to_agg(public.jsonb_stats_agg(v_sd.code, public.stat(0.0::float8))) -> v_sd.code)
            );
        ELSIF v_sd.type_text = 'string' THEN
            v_catalog_summary := v_catalog_summary || jsonb_build_object(
                v_sd.code,
                (public.jsonb_stats_to_agg(public.jsonb_stats_agg(v_sd.code, public.stat(''::text))) -> v_sd.code)
            );
        ELSIF v_sd.type_text = 'bool' THEN
            v_catalog_summary := v_catalog_summary || jsonb_build_object(
                v_sd.code,
                (public.jsonb_stats_to_agg(public.jsonb_stats_agg(v_sd.code, public.stat(false))) -> v_sd.code)
            );
        ELSE
            -- New stat_type added to the enum without updating this function — fail loudly
            -- (catalog would be silently incomplete; HINTs would drop the unknown type).
            RAISE EXCEPTION 'statistical_history_highcharts: unhandled stat_type %', v_sd.type_text;
        END IF;
    END LOOP;

    -- Resolve each requested code in caller-supplied order.
    IF p_series_codes IS NOT NULL AND cardinality(p_series_codes) > 0 THEN
        FOREACH v_req_code IN ARRAY p_series_codes LOOP
            -- §A: collapse trailing dots and repeated internal dot runs so
            -- 'stats_summary.' → 'stats_summary' (top-level partial),
            -- 'stats_summary..turnover' → 'stats_summary.turnover' (no empty segment in v_path).
            v_req_code := regexp_replace(v_req_code, '\.+$', '');
            v_req_code := regexp_replace(v_req_code, '\.{2,}', '.', 'g');

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

                -- Resolve the path shape from real data first; fall back to the
                -- schema-derived catalog when the filter slice is empty. This unifies
                -- the user-visible vocabulary across empty- and present-data cases:
                -- `stats_summary.employees` on year=9999 must say "Incomplete series
                -- code" (not "Unknown") just as it does on a year with data, since
                -- the path IS structurally valid. Data lookup in the `stats_pairs`
                -- CTE below still reads `b.stats_summary` from real rows — only the
                -- shape/acceptance check shifts to catalog when data is absent.
                v_node := COALESCE(v_merged_summary #> v_path, v_catalog_summary #> v_path);

                CASE jsonb_typeof(v_node)
                    WHEN 'number' THEN
                        INSERT INTO stats_path_buffer(code, jsonb_path) VALUES (v_req_code, v_path)
                        ON CONFLICT (code) DO NOTHING;  -- caller may pass a duplicate; first wins
                    WHEN 'object' THEN
                        v_msgs := v_msgs || format('Incomplete series code "%s"', v_req_code);
                        -- HINT enumerates valid sub-keys from the SCHEMA-DERIVED catalog
                        -- (independent of whether real data is populated). COALESCE retained
                        -- as defensive fallback for paths catalog can't enumerate.
                        v_hints := v_hints || COALESCE(
                            (SELECT 'Try one of: ' || string_agg(format('%s.%s', v_req_code, k), ', ' ORDER BY k)
                               FROM jsonb_object_keys(v_catalog_summary #> v_path) AS k
                              WHERE k <> 'type'),
                            format('No completions available under "%s"', v_req_code)
                        );
                    ELSE
                        -- §B: real data has nothing at this path. Try to give a useful HINT
                        -- from the catalog: if v_path[1] is a known stat, list its leaves;
                        -- otherwise list valid top-level stats. Plan calls this the
                        -- "bogus leaf" enhancement; extended to cardinality >= 1 so the
                        -- empty-data `stats_summary.<known_stat>` case also gets help.
                        v_msgs := v_msgs || format('Unknown series code "%s"', v_req_code);
                        IF cardinality(v_path) >= 1 AND jsonb_typeof(v_catalog_summary -> v_path[1]) = 'object' THEN
                            v_hints := v_hints || (
                                SELECT 'Try one of: ' || string_agg(format('stats_summary.%s.%s', v_path[1], k), ', ' ORDER BY k)
                                  FROM jsonb_object_keys(v_catalog_summary -> v_path[1]) AS k
                                 WHERE k <> 'type'
                            );
                        ELSIF cardinality(v_path) >= 1 AND v_catalog_summary <> '{}'::jsonb THEN
                            v_hints := v_hints || (
                                SELECT 'Try one of: ' || string_agg('stats_summary.' || k, ', ' ORDER BY k)
                                  FROM jsonb_object_keys(v_catalog_summary) AS k
                            );
                        END IF;
                END CASE;

            ELSE
                -- §C: caller passed a code that's neither a known static series nor a
                -- `stats_summary[.…]` path — likely a typo (`jsonb_stats`, `tunover`, …).
                -- Suggest the full set of valid top-level codes: static catalog (minus the
                -- bootstrap 'stats_summary' partial) UNION `stats_summary.<stat>` from catalog.
                v_msgs := v_msgs || format('Unknown series code "%s"', v_req_code);
                v_hints := v_hints || (
                    SELECT 'Try one of: ' || string_agg(code, ', ' ORDER BY code) FROM (
                        SELECT code FROM series_definition WHERE code <> 'stats_summary'
                        UNION ALL
                        SELECT 'stats_summary.' || k FROM jsonb_object_keys(v_catalog_summary) AS k
                    ) AS t
                );
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
$function$;

END;
