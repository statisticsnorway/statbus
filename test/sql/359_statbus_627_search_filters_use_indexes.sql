BEGIN;

\i test/setup.sql

-- STATBUS-627: every filter the search page sends to statistical_unit is served by an index.
--
-- The search page (app/src/app/search/filters/url-search-params.ts) filters statistical_unit
-- through PostgREST. Each filter below is the SQL PostgREST makes of one search parameter.
-- An index serves a filter only when it is built on exactly the filtered expression: the
-- statistic filter sends stats_summary->code->'sum' (jsonb), and an index on
-- stats_summary->code->>'sum' (text) is never used. With sequential scans priced out, the
-- planner picks an index whenever one can serve the filter. An index serves the filter when the
-- filter is the index scan's condition (Index Cond); a scan that walks an unrelated index and
-- applies the filter to every row (Filter) reads the whole table and does not count.
-- Statistics and identifier types come from the enabled definitions, so a new statistic or
-- identifier type is covered as soon as it is enabled.

SET LOCAL enable_seqscan = off;

CREATE FUNCTION pg_temp.filter_uses_index(p_sql text) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE
    v_line text;
    v_index boolean := false;
BEGIN
    FOR v_line IN EXECUTE 'EXPLAIN (COSTS OFF) ' || p_sql LOOP
        IF v_line ~ 'Index Cond:' THEN
            v_index := true;
        END IF;
    END LOOP;
    RETURN v_index;
END;
$$;

CREATE TEMP TABLE search_filter (filter text, sql text) ON COMMIT DROP;
INSERT INTO search_filter VALUES
    ('search (fts)',                       $q$SELECT unit_id FROM public.statistical_unit WHERE search @@ to_tsquery('simple', 'norsk:*')$q$),
    ('unit_type in',                       $q$SELECT unit_id FROM public.statistical_unit WHERE unit_type = ANY ('{enterprise,legal_unit}')$q$),
    ('legal_form_code in',                 $q$SELECT unit_id FROM public.statistical_unit WHERE legal_form_code = ANY ('{AS,ENK}')$q$),
    ('physical_region_path cd',            $q$SELECT unit_id FROM public.statistical_unit WHERE physical_region_path <@ '03'::ltree$q$),
    ('sector_path cd',                     $q$SELECT unit_id FROM public.statistical_unit WHERE sector_path <@ '1100'::ltree$q$),
    ('primary_activity_category_path cd',  $q$SELECT unit_id FROM public.statistical_unit WHERE primary_activity_category_path <@ 'A.01'::ltree$q$),
    ('status_code in',                     $q$SELECT unit_id FROM public.statistical_unit WHERE status_code = ANY ('{active}')$q$),
    ('domestic eq',                        $q$SELECT unit_id FROM public.statistical_unit WHERE domestic = false$q$),
    ('unit_size_code in',                  $q$SELECT unit_id FROM public.statistical_unit WHERE unit_size_code = ANY ('{micro}')$q$),
    ('last_edit_by_user_id in',            $q$SELECT unit_id FROM public.statistical_unit WHERE last_edit_by_user_id = ANY ('{1}')$q$),
    ('data_source_ids ov',                 $q$SELECT unit_id FROM public.statistical_unit WHERE data_source_ids && '{1}'::integer[]$q$);
INSERT INTO search_filter
SELECT format('external_idents->>%s eq', code),
       format($q$SELECT unit_id FROM public.statistical_unit WHERE external_idents->>%L = '999'$q$, code)
FROM public.external_ident_type_enabled;
INSERT INTO search_filter
SELECT format('stats_summary->%s->sum gte', code),
       format($q$SELECT unit_id FROM public.statistical_unit WHERE stats_summary->%L->'sum' >= '100'::jsonb$q$, code)
FROM public.stat_definition_enabled;

\echo "627.1 every search filter on statistical_unit uses an index"
SELECT filter, pg_temp.filter_uses_index(sql) AS uses_index
FROM search_filter
ORDER BY filter;

-- The search table sorts by a column (app/src/app/search/components/statistical-unit-table-header.tsx)
-- in two directions, asc and desc.nullslast, always followed by unit_type, unit_id
-- (app/src/atoms/search.ts). For a page from the end, the search reverses the order
-- (reverseParamsForTailPage), so each order is also read backwards. A sort is served when the
-- first page comes straight from an index in that order: the plan has no Sort step. The test
-- database holds no units, where sorting nothing costs nothing, so sorting is priced out as
-- sequential scans are above: the planner then reads an index in order whenever one exists.
SET LOCAL enable_sort = off;
CREATE FUNCTION pg_temp.sort_uses_index(p_order text) RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE
    v_line text;
    v_sorted boolean := false;
    v_index boolean := false;
BEGIN
    FOR v_line IN EXECUTE 'EXPLAIN (COSTS OFF) SELECT unit_id FROM public.statistical_unit ORDER BY '
                          || p_order || ' LIMIT 10' LOOP
        IF v_line ~ 'Sort' THEN v_sorted := true; END IF;
        IF v_line ~ 'Index (Only )?Scan' THEN v_index := true; END IF;
    END LOOP;
    RETURN v_index AND NOT v_sorted;
END;
$$;

CREATE TEMP TABLE search_sort (sort_key text, expression text) ON COMMIT DROP;
INSERT INTO search_sort VALUES
    ('name', 'name'),
    ('physical_region_path', 'physical_region_path'),
    ('sector_path', 'sector_path'),
    ('legal_form_code', 'legal_form_code'),
    ('primary_activity_category_path', 'primary_activity_category_path'),
    ('secondary_activity_category_path', 'secondary_activity_category_path'),
    ('birth_date', 'birth_date'),
    ('death_date', 'death_date'),
    ('last_edit_at', 'last_edit_at');
INSERT INTO search_sort
SELECT format('stats_summary->%s->sum', code), format($e$(stats_summary->%L->'sum')$e$, code)
FROM public.stat_definition_enabled;

\echo "627.2 every search sort on statistical_unit reads an index in order, forwards and for pages from the end"
SELECT s.sort_key, d.direction,
       pg_temp.sort_uses_index(format(d.template, s.expression)) AS uses_index
FROM search_sort AS s
CROSS JOIN (VALUES
    ('asc',                      '%s ASC, unit_type ASC, unit_id ASC'),
    ('desc.nullslast',           '%s DESC NULLS LAST, unit_type ASC, unit_id ASC'),
    ('asc, from the end',        '%s DESC NULLS FIRST, unit_type DESC, unit_id DESC'),
    ('desc.nullslast, from end', '%s ASC NULLS FIRST, unit_type DESC, unit_id DESC')
) AS d (direction, template)
ORDER BY s.sort_key, d.direction;

ROLLBACK;
