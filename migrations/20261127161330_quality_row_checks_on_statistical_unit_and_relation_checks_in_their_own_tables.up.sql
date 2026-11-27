-- Migration 20261127161330: quality row checks on statistical_unit and relation checks in their own tables
-- h9mhxe part 2 (design report 0pn35h, owner decision 2026-11-27). A row check is decided by one
-- statistical_unit row and is a generated element of that row's quality_check_ids. A relation check
-- compares a legal unit with its establishments and has its own table, filled per hash partition by
-- worker.derive_quality. The catalogue (part 1) becomes public.quality_check with its switch.
BEGIN;

-- ######## the catalogue takes the name quality_check, with the switch ########
ALTER TABLE public.quality_check_catalogue ADD COLUMN switched_on boolean NOT NULL DEFAULT false;
-- An installation keeps exactly the checks it showed (1tx1ed): every check in quality_check_switched_on.
UPDATE public.quality_check_catalogue AS qc SET switched_on = true
WHERE EXISTS (SELECT 1 FROM public.quality_check_switched_on AS qs
              WHERE qs.rule = qc.rule AND COALESCE(qs.stat_definition_id, 0) = COALESCE(qc.stat_definition_id, 0));

DROP FUNCTION public.statistical_unit_quality(public.quality_rule, date, integer);
DROP VIEW public.quality_check;
DROP TABLE public.quality_check_switched_on;

ALTER TABLE public.quality_check_catalogue RENAME TO quality_check;
ALTER SEQUENCE public.quality_check_catalogue_id_seq RENAME TO quality_check_id_seq;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_catalogue_pkey TO quality_check_pkey;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_catalogue_rule_variable_key TO quality_check_rule_variable_key;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_catalogue_id_variable_key TO quality_check_id_variable_key;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_catalogue_variable_matches_rule TO quality_check_variable_matches_rule;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_catalogue_kind_matches_rule TO quality_check_kind_matches_rule;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_catalogue_stat_definition_id_fkey TO quality_check_stat_definition_id_fkey;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_catalogue_id_not_null TO quality_check_id_not_null;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_catalogue_rule_not_null TO quality_check_rule_not_null;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_catalogue_kind_not_null TO quality_check_kind_not_null;
ALTER TABLE public.quality_check RENAME CONSTRAINT quality_check_catalogue_priority_not_null TO quality_check_priority_not_null;
ALTER POLICY quality_check_catalogue_admin_user_manage ON public.quality_check RENAME TO quality_check_admin_user_manage;
ALTER POLICY quality_check_catalogue_authenticated_read ON public.quality_check RENAME TO quality_check_authenticated_read;
ALTER POLICY quality_check_catalogue_regular_user_read ON public.quality_check RENAME TO quality_check_regular_user_read;

COMMENT ON TABLE public.quality_check IS
  'Every data-quality check of this installation with its integer id (h9mhxe): each rule that is not per variable once, with a fixed id (1 missing_region, 2 missing_activity_category, 3 missing_physical_location, 4 establishment_activity_differs, 7 secondary_activity_equals_primary), and each per-variable rule once per summed variable (stat_definition of type int or float), with an id from 101 up given when the variable is created and kept by the stat_definition lifecycle callback (public.quality_check_catalogue_generate / _cleanup). The id is what findings store: a row check in statistical_unit.quality_check_ids, a relation check as check_id in its table (public.quality_establishment_activity_differs, public.quality_legal_unit_establishment_stat). It is never reused, so a stored id always names the same check. Readers show the checks public.in_use says apply. Admins switch checks on Admin > Data quality checks (switched_on).';
COMMENT ON COLUMN public.quality_check.switched_on IS
  'Whether the dashboard''s Data quality section and the search''s Quality filter show the check (1tx1ed). A check starts off, a new variable''s checks too; a fresh installation and reset''s customisation scope switch on the starting set (public.quality_check_starting_set). A switched-off check is still computed, so switching it on shows its number at once. A disabled variable''s check keeps its switch for when the variable is enabled again.';
COMMENT ON CONSTRAINT quality_check_rule_variable_key ON public.quality_check IS
  'A check is a rule and its variable (NULL counting as a value): it is in the catalogue once.';
COMMENT ON CONSTRAINT quality_check_id_variable_key ON public.quality_check IS
  'Target of public.quality_legal_unit_establishment_stat''s (check_id, stat_definition_id) foreign key, so a comparison''s variable is its check''s variable.';
COMMENT ON CONSTRAINT quality_check_variable_matches_rule ON public.quality_check IS
  'A per-variable check names its variable and every other check names none (public.quality_rule_per_stat).';
COMMENT ON CONSTRAINT quality_check_kind_matches_rule ON public.quality_check IS
  'A check''s kind is its rule''s kind (public.quality_rule_kind).';

CREATE FUNCTION public.in_use(public.quality_check)
 RETURNS boolean
 LANGUAGE sql
 STABLE PARALLEL SAFE
AS $in_use$
    SELECT $1.stat_definition_id IS NULL
        OR EXISTS (SELECT 1 FROM public.stat_definition AS sd
                   WHERE sd.id = $1.stat_definition_id
                     AND sd.enabled
                     AND sd.type IN ('int', 'float')
                     AND sd.lu_es_rollup = 'max')
$in_use$;
COMMENT ON FUNCTION public.in_use(public.quality_check) IS
  'Whether a check applies now, a computed field of public.quality_check (?select=*,in_use): a check without a variable always; a per-variable check while its variable is enabled, of type int or float, and with lu_es_rollup max, the variables public.legal_unit_establishment_stat_comparison compares (s465ff). The dashboard, the search and the admin page show only checks in use, so disabling a variable takes its checks away at once with no unit edited, and enabling it brings them back with their switches (bxt67q); the next worker.derive_quality rewrites its findings.';

CREATE OR REPLACE PROCEDURE public.quality_check_catalogue_generate()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- One check per per-variable rule and summed variable; an existing check keeps its id and
    -- follows its variable's priority. Ids come in rule then variable order, so a replay gives
    -- the same ids. Only missing checks are inserted: an INSERT ... ON CONFLICT would draw an id
    -- for every existing check on every call.
    UPDATE public.quality_check AS qc
    SET priority = array_position(enum_range(NULL::public.quality_rule), qc.rule) * 1000 + sd.priority
    FROM public.stat_definition AS sd
    WHERE qc.stat_definition_id = sd.id
      AND qc.priority <> array_position(enum_range(NULL::public.quality_rule), qc.rule) * 1000 + sd.priority;

    INSERT INTO public.quality_check (rule, stat_definition_id, kind, priority)
    SELECT r.rule, sd.id, public.quality_rule_kind(r.rule),
           array_position(enum_range(NULL::public.quality_rule), r.rule) * 1000 + sd.priority
    FROM unnest(enum_range(NULL::public.quality_rule)) AS r(rule)
    JOIN public.stat_definition AS sd ON sd.type IN ('int', 'float')
    WHERE public.quality_rule_per_stat(r.rule)
      AND NOT EXISTS (
          SELECT FROM public.quality_check AS qc
          WHERE qc.rule = r.rule AND qc.stat_definition_id = sd.id)
    ORDER BY r.rule, sd.priority, sd.id;
END;
$procedure$;

CREATE OR REPLACE PROCEDURE public.quality_check_catalogue_cleanup()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- A deleted variable's checks went with it (ON DELETE CASCADE); a variable that is no longer
    -- summed loses its checks here.
    DELETE FROM public.quality_check AS qc
    USING public.stat_definition AS sd
    WHERE qc.stat_definition_id = sd.id
      AND sd.type NOT IN ('int', 'float');
END;
$procedure$;

-- ######## row checks: generated on statistical_unit ########
-- Rewrites statistical_unit once (11 min on the Norway copy, 3.0 M rows).
ALTER TABLE public.statistical_unit ADD COLUMN quality_check_ids integer[] GENERATED ALWAYS AS (
    array_remove(ARRAY[
        CASE WHEN unit_type IN ('legal_unit', 'establishment') AND domestic AND physical_country_id IS NOT NULL AND physical_region_path IS NULL THEN 1 END,
        CASE WHEN unit_type IN ('legal_unit', 'establishment') AND primary_activity_category_path IS NULL THEN 2 END,
        CASE WHEN unit_type IN ('legal_unit', 'establishment') AND physical_country_id IS NULL THEN 3 END,
        CASE WHEN unit_type IN ('legal_unit', 'establishment') AND secondary_activity_category_id = primary_activity_category_id THEN 7 END
    ], NULL)) STORED;
COMMENT ON COLUMN public.statistical_unit.quality_check_ids IS
  'The row checks this statistical_unit row fails (h9mhxe), by public.quality_check.id: 1 missing_region (a legal unit or establishment located in the installation''s country, domestic, without a region), 2 missing_activity_category (no primary activity category), 3 missing_physical_location (no physical location), 7 secondary_activity_equals_primary. Generated from the row''s own columns, so every write of the row (full refresh, partial flush) sets it in the same transaction and it costs no derive. A new row check is a new id here and in public.quality_check, with its rule in public.quality_rule. Relation checks are in their own tables.';
CREATE OR REPLACE FUNCTION admin.create_statistical_unit_ui_indices()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Every index here serves a query on statistical_unit; its COMMENT names the query.
    -- The search page's filters and sorts are listed in app/src/app/search/filters/url-search-params.ts
    -- and app/src/atoms/search.ts; test/sql/359 checks that each one reads an index.

    -- Lookups by the derive pipeline, reports and unit pages.
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_unit_type ON public.statistical_unit (unit_type);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_establishment_id ON public.statistical_unit (unit_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_primary_activity_category_id ON public.statistical_unit (primary_activity_category_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_secondary_activity_category_id ON public.statistical_unit (secondary_activity_category_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_region_id ON public.statistical_unit (physical_region_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_physical_country_id ON public.statistical_unit (physical_country_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_sector_id ON public.statistical_unit (sector_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_legal_form_id ON public.statistical_unit (legal_form_id);

    -- Search filters.
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_domestic ON public.statistical_unit (domestic);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_status_code ON public.statistical_unit (status_code);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_unit_size_code ON public.statistical_unit (unit_size_code);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_last_edit_by_user_id ON public.statistical_unit (last_edit_by_user_id);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_search ON public.statistical_unit USING GIN (search);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_data_source_ids ON public.statistical_unit USING GIN (data_source_ids public.gin__int_ops);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_external_idents ON public.statistical_unit USING GIN (external_idents jsonb_path_ops);

    -- Path filters (descendant of a chosen code: GiST).
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_physical_region_path ON public.statistical_unit USING GIST (physical_region_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_sector_path ON public.statistical_unit USING GIST (sector_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_primary_activity_category_path ON public.statistical_unit USING GIST (primary_activity_category_path);
    CREATE INDEX IF NOT EXISTS idx_gist_statistical_unit_tag_paths ON public.statistical_unit USING GIST (tag_paths);

    -- Quality checks (h9mhxe): the search's Quality filter (quality_check_ids contains a check) and the
    -- dashboard's count of every row check at an instant, which reads only the rows with a check. The
    -- count's index includes the existence dates' own columns, so the count is an index-only scan:
    -- an index on expressions alone needs the heap to recheck them (Norway copy: 350-500 ms from the
    -- heap, 36-42 ms index-only).
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_quality_check_ids ON public.statistical_unit USING GIN (quality_check_ids public.gin__int_ops);
    CREATE INDEX IF NOT EXISTS idx_statistical_unit_quality_check_count ON public.statistical_unit
        (public.unit_existence_from(valid_from, birth_date), public.unit_existence_until(valid_until, death_date))
        INCLUDE (quality_check_ids, valid_from, birth_date, valid_until, death_date) WHERE quality_check_ids <> '{}';

    -- Search sorts: one index per direction, ending in the search's tie-break (unit_type, unit_id).
    -- The asc index also serves the column's equality filter (legal_form_code in (...)).
    CREATE INDEX IF NOT EXISTS su_sort_name_asc ON public.statistical_unit (name, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_name_desc ON public.statistical_unit (name DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_physical_region_path_asc ON public.statistical_unit (physical_region_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_physical_region_path_desc ON public.statistical_unit (physical_region_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_sector_path_asc ON public.statistical_unit (sector_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_sector_path_desc ON public.statistical_unit (sector_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_legal_form_code_asc ON public.statistical_unit (legal_form_code, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_legal_form_code_desc ON public.statistical_unit (legal_form_code DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_primary_activity_category_path_asc ON public.statistical_unit (primary_activity_category_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_primary_activity_category_path_desc ON public.statistical_unit (primary_activity_category_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_secondary_activity_category_path_asc ON public.statistical_unit (secondary_activity_category_path, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_secondary_activity_category_path_desc ON public.statistical_unit (secondary_activity_category_path DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_birth_date_asc ON public.statistical_unit (birth_date, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_birth_date_desc ON public.statistical_unit (birth_date DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_death_date_asc ON public.statistical_unit (death_date, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_death_date_desc ON public.statistical_unit (death_date DESC NULLS LAST, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_last_edit_at_asc ON public.statistical_unit (last_edit_at, unit_type, unit_id);
    CREATE INDEX IF NOT EXISTS su_sort_last_edit_at_desc ON public.statistical_unit (last_edit_at DESC NULLS LAST, unit_type, unit_id);

    -- Per identifier type and per statistic (su_ei_*, su_ss_*): admin.generate_statistical_unit_jsonb_indices().
    CALL admin.generate_statistical_unit_jsonb_indices();

    PERFORM admin.comment_statistical_unit_indices();
    RAISE DEBUG 'Created all statistical_unit UI indices';
END;
$function$;

CREATE OR REPLACE FUNCTION admin.comment_statistical_unit_indices()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    r RECORD;
    v_comment text;
BEGIN
    FOR r IN
        SELECT c.relname AS indexname
          FROM pg_index AS i JOIN pg_class AS c ON c.oid = i.indexrelid
         WHERE i.indrelid = 'public.statistical_unit'::regclass
           -- These two carry their own comments, written where they were made.
           AND c.relname NOT IN ('idx_statistical_unit_hash_slot', 'statistical_unit_unit_idx')
    LOOP
        v_comment := CASE
            WHEN r.indexname = 'statistical_unit_temporal_pk' THEN
                'Temporal primary key (unit_type, unit_id, valid_range): one row per unit and period.'
            WHEN r.indexname IN ('idx_statistical_unit_unit_type', 'idx_statistical_unit_establishment_id') THEN
                'Unit pages and reports look units up by type and id.'
            WHEN r.indexname = 'idx_statistical_unit_last_edit_by_user_id' THEN
                'Search filter: last edited by (last_edit_by_user_id in ...).'
            WHEN r.indexname ~ '^idx_statistical_unit_.*_id$' THEN
                'Derive pipeline and reports join statistical_unit to its classification by id.'
            WHEN r.indexname = 'idx_statistical_unit_domestic' THEN 'Search filter: domestic.'
            WHEN r.indexname = 'idx_statistical_unit_status_code' THEN 'Search filter: status (status_code in ...).'
            WHEN r.indexname = 'idx_statistical_unit_unit_size_code' THEN 'Search filter: unit size (unit_size_code in ...).'
            WHEN r.indexname = 'idx_statistical_unit_search' THEN 'Search filter: free text (search, full-text query).'
            WHEN r.indexname = 'idx_statistical_unit_data_source_ids' THEN 'Search filter: data source (data_source_ids overlaps ...).'
            WHEN r.indexname = 'idx_statistical_unit_quality_check_ids' THEN 'Search filter: Quality (quality_check_ids contains a row check''s id, h9mhxe).'
            WHEN r.indexname = 'idx_statistical_unit_quality_check_count' THEN 'Dashboard: the count of every row check at an instant (public.quality_check_count), over the rows that have a check only.'
            WHEN r.indexname = 'idx_gist_statistical_unit_external_idents' THEN 'Identifier lookups by containment (external_idents @> ...).'
            WHEN r.indexname ~ '^idx_gist_statistical_unit_' THEN
                format('Search filter: %s under a chosen code (ltree descendant, cd.).',
                       regexp_replace(r.indexname, '^idx_gist_statistical_unit_', ''))
            WHEN r.indexname ~ '^su_sort_.*_asc$' THEN
                format('Search sort: %s ascending, then unit_type, unit_id; read backwards for a page from the end of a descending sort. Also serves equality filters on the column.',
                       regexp_replace(r.indexname, '^su_sort_(.*)_asc$', '\1'))
            WHEN r.indexname ~ '^su_sort_.*_desc$' THEN
                format('Search sort: %s descending with nulls last, then unit_type, unit_id; read backwards for a page from the end of an ascending sort.',
                       regexp_replace(r.indexname, '^su_sort_(.*)_desc$', '\1'))
            WHEN r.indexname ~ '^su_ss_.*_sum_asc_idx$' THEN
                format('Search filter and sort on statistic %s (stats_summary->code->''sum''): ascending, then unit_type, unit_id. Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ss_(.*)_sum_asc_idx$', '\1'))
            WHEN r.indexname ~ '^su_ss_.*_sum_desc_idx$' THEN
                format('Search sort on statistic %s (stats_summary->code->''sum''): descending with nulls last, then unit_type, unit_id. Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ss_(.*)_sum_desc_idx$', '\1'))
            WHEN r.indexname ~ '^su_ei_.*_ltree_gist_idx$' THEN
                format('Search filter: hierarchical identifier %s matched by pattern. Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ei_(.*)_ltree_gist_idx$', '\1'))
            WHEN r.indexname ~ '^su_ei_.*_idx$' THEN
                format('Search filter: identifier %s (external_idents->>code). Built by admin.generate_statistical_unit_jsonb_indices.',
                       regexp_replace(r.indexname, '^su_ei_(.*)_idx$', '\1'))
        END;
        IF v_comment IS NULL THEN
            RAISE EXCEPTION 'statistical_unit index % has no stated purpose: add it to admin.comment_statistical_unit_indices() with the query it serves, or drop it', r.indexname;
        END IF;
        EXECUTE format('COMMENT ON INDEX public.%I IS %L', r.indexname, v_comment);
    END LOOP;
END;
$function$;

-- The function's IF NOT EXISTS notices for the indexes that are there are noise here.
SET LOCAL client_min_messages TO WARNING;
SELECT admin.create_statistical_unit_ui_indices();
RESET client_min_messages;

-- The staging table and the flush need no change: the flush MERGE names its columns and the
-- column is generated on statistical_unit, the MERGE''s target. The partial function returns
-- statistical_unit''s rowtype, so it names the column too.
CREATE OR REPLACE FUNCTION import.get_statistical_unit_data_partial(p_unit_type statistical_unit_type, p_id_ranges int4multirange)
 RETURNS SETOF statistical_unit
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_ids INT[] := public.int4multirange_to_array(p_id_ranges);
BEGIN
    IF p_unit_type = 'establishment' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.latitude, t.longitude, t.altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot,
            -- quality_check_ids is generated on statistical_unit; the staging table has no such column.
            NULL::integer[] AS quality_check_ids
        FROM public.timeline_establishment t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.establishment_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.establishment_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'legal_unit' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.latitude, t.longitude, t.altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            t.stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot,
            -- quality_check_ids is generated on statistical_unit; the staging table has no such column.
            NULL::integer[] AS quality_check_ids
        FROM public.timeline_legal_unit t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.legal_unit_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.legal_unit_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'enterprise' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, eia2.external_idents, eia3.external_idents, '{}'::jsonb) AS external_idents,
            t.name::varchar, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.latitude, t.longitude, t.altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            NULL::JSONB AS stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot,
            -- quality_check_ids is generated on statistical_unit; the staging table has no such column.
            NULL::integer[] AS quality_check_ids
        FROM public.timeline_enterprise t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.enterprise_id = t.unit_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.establishment_id = t.primary_establishment_id) eia2 ON true
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.legal_unit_id = t.primary_legal_unit_id) eia3 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.enterprise_id = t.unit_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);

    ELSIF p_unit_type = 'power_group' THEN
        RETURN QUERY
        SELECT t.unit_type, t.unit_id, t.valid_from, t.valid_to, t.valid_until,
            COALESCE(eia1.external_idents, '{}'::jsonb) AS external_idents,
            t.name::varchar, t.birth_date, t.death_date, t.search,
            t.primary_activity_category_id, t.primary_activity_category_path, t.primary_activity_category_code,
            t.secondary_activity_category_id, t.secondary_activity_category_path, t.secondary_activity_category_code,
            t.activity_category_paths, t.sector_id, t.sector_path, t.sector_code, t.sector_name,
            t.data_source_ids, t.data_source_codes, t.legal_form_id, t.legal_form_code, t.legal_form_name,
            t.physical_address_part1, t.physical_address_part2, t.physical_address_part3, t.physical_postcode, t.physical_postplace,
            t.physical_region_id, t.physical_region_path, t.physical_region_code, t.physical_country_id, t.physical_country_iso_2,
            t.latitude, t.longitude, t.altitude, t.domestic,
            t.postal_address_part1, t.postal_address_part2, t.postal_address_part3, t.postal_postcode, t.postal_postplace,
            t.postal_region_id, t.postal_region_path, t.postal_region_code, t.postal_country_id, t.postal_country_iso_2,
            t.web_address, t.email_address, t.phone_number, t.landline, t.mobile_number, t.fax_number,
            t.unit_size_id, t.unit_size_code, t.status_id, t.status_code, t.used_for_counting,
            t.last_edit_comment, t.last_edit_by_user_id, t.last_edit_at, t.has_legal_unit,
            t.related_establishment_ids, t.excluded_establishment_ids, t.included_establishment_ids,
            t.related_legal_unit_ids, t.excluded_legal_unit_ids, t.included_legal_unit_ids,
            t.related_enterprise_ids, t.excluded_enterprise_ids, t.included_enterprise_ids,
            NULL::JSONB AS stats, t.stats_summary,
            array_length(t.included_establishment_ids, 1) AS included_establishment_count,
            array_length(t.included_legal_unit_ids, 1) AS included_legal_unit_count,
            array_length(t.included_enterprise_ids, 1) AS included_enterprise_count,
            COALESCE(tpa.tag_paths, ARRAY[]::public.ltree[]) AS tag_paths,
            daterange(t.valid_from, t.valid_until) AS valid_range,
            public.hash_slot(t.unit_type, t.unit_id) AS hash_slot,
            -- quality_check_ids is generated on statistical_unit; the staging table has no such column.
            NULL::integer[] AS quality_check_ids
        FROM public.timeline_power_group t
        LEFT JOIN LATERAL (SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text)) AS external_idents FROM public.external_ident ei JOIN public.external_ident_type eit ON ei.type_id = eit.id WHERE ei.power_group_id = t.power_group_id) eia1 ON true
        LEFT JOIN LATERAL (SELECT array_agg(tag.path ORDER BY tag.path) AS tag_paths FROM public.tag_for_unit tfu JOIN public.tag ON tfu.tag_id = tag.id WHERE tfu.power_group_id = t.power_group_id) tpa ON true
        WHERE t.unit_id = ANY(v_ids);
    END IF;
END;
$function$;

-- relevant_statistical_units returns statistical_unit's rowtype by an explicit list: it names the column.
CREATE OR REPLACE FUNCTION public.relevant_statistical_units(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS SETOF statistical_unit
 LANGUAGE sql
 STABLE
AS $function$
    -- Step 1: Find the enterprise row directly via temporal PK index
    WITH root_unit AS (
        SELECT su.unit_type, su.unit_id,
               su.related_legal_unit_ids,
               su.related_establishment_ids,
               su.external_idents
        FROM public.statistical_unit AS su
        WHERE su.unit_type = 'enterprise'
          AND su.unit_id = public.statistical_unit_enterprise_id($1, $2, $3)
          AND public.existence_from(su) <= $3 AND $3 < public.existence_until(su)
    -- Step 2: Collect all relevant (unit_type, unit_id) pairs from arrays
    ), relevant_ids AS (
        SELECT 'enterprise'::statistical_unit_type AS unit_type, ru.unit_id FROM root_unit AS ru
        UNION ALL
        SELECT 'legal_unit'::statistical_unit_type, unnest(ru.related_legal_unit_ids) FROM root_unit AS ru
        UNION ALL
        SELECT 'establishment'::statistical_unit_type, unnest(ru.related_establishment_ids) FROM root_unit AS ru
    -- Step 3: Single join back to get full rows, ordered by external ident priority
    ), full_units AS (
        SELECT su.*
            , first_external.ident AS first_external_ident
        FROM relevant_ids AS ri
        JOIN public.statistical_unit AS su
          ON su.unit_type = ri.unit_type
         AND su.unit_id = ri.unit_id
         AND public.existence_from(su) <= $3 AND $3 < public.existence_until(su)
        LEFT JOIN LATERAL (
            SELECT eit.code, (su.external_idents->>eit.code)::text AS ident
            FROM public.external_ident_type AS eit
            ORDER BY eit.priority
            LIMIT 1
        ) first_external ON true
        ORDER BY su.unit_type, first_external_ident NULLS LAST, su.unit_id
    )
    SELECT unit_type
         , unit_id
         , valid_from
         , valid_to
         , valid_until
         , external_idents
         , name
         , birth_date
         , death_date
         , search
         , primary_activity_category_id
         , primary_activity_category_path
         , primary_activity_category_code
         , secondary_activity_category_id
         , secondary_activity_category_path
         , secondary_activity_category_code
         , activity_category_paths
         , sector_id
         , sector_path
         , sector_code
         , sector_name
         , data_source_ids
         , data_source_codes
         , legal_form_id
         , legal_form_code
         , legal_form_name
         --
         , physical_address_part1
         , physical_address_part2
         , physical_address_part3
         , physical_postcode
         , physical_postplace
         , physical_region_id
         , physical_region_path
         , physical_region_code
         , physical_country_id
         , physical_country_iso_2
         , latitude
         , longitude
         , altitude
         --
         , domestic
         --
         , postal_address_part1
         , postal_address_part2
         , postal_address_part3
         , postal_postcode
         , postal_postplace
         , postal_region_id
         , postal_region_path
         , postal_region_code
         , postal_country_id
         , postal_country_iso_2
         --
         , web_address
         , email_address
         , phone_number
         , landline
         , mobile_number
         , fax_number
         --
         , unit_size_id
         , unit_size_code
         --
         , status_id
         , status_code
         , used_for_counting
         --
         , last_edit_comment
         , last_edit_by_user_id
         , last_edit_at
         --
         , has_legal_unit
         , related_establishment_ids
         , excluded_establishment_ids
         , included_establishment_ids
         , related_legal_unit_ids
         , excluded_legal_unit_ids
         , included_legal_unit_ids
         , related_enterprise_ids
         , excluded_enterprise_ids
         , included_enterprise_ids
         , stats
         , stats_summary
         , included_establishment_count
         , included_legal_unit_count
         , included_enterprise_count
         , tag_paths
         , daterange(valid_from, valid_until) AS valid_range
         , hash_slot
         , quality_check_ids
    FROM full_units;
$function$;

-- ######## relation checks: a table per kind of relation, rederived per partition ########
ALTER TABLE public.quality_establishment_activity_differs
    ALTER COLUMN legal_unit_activity_category_id DROP NOT NULL,
    ALTER COLUMN establishment_activity_category_id DROP NOT NULL,
    ADD CONSTRAINT quality_establishment_activity_differs_statistical_unit_fkey
        FOREIGN KEY (unit_type, unit_id, PERIOD valid_range)
        REFERENCES public.statistical_unit (unit_type, unit_id, PERIOD valid_range) NOT ENFORCED;
COMMENT ON COLUMN public.quality_establishment_activity_differs.legal_unit_activity_category_id IS
  'The legal unit''s primary activity category; NULL when it has none and its primary establishment has one.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.establishment_activity_category_id IS
  'The primary establishment''s primary activity category, which differs from the legal unit''s; NULL when it has none and the legal unit has one.';
COMMENT ON CONSTRAINT quality_establishment_activity_differs_statistical_unit_fkey ON public.quality_establishment_activity_differs IS
  'NOT ENFORCED: names the statistical_unit row for readers and for PostgREST''s embed (statistical_unit?select=*,quality_establishment_activity_differs!inner()); derive rewrites statistical_unit freely and the next worker.derive_quality makes this table right again. statistical_unit_refresh and reset name this table in their TRUNCATE.';
ALTER TABLE public.quality_legal_unit_establishment_stat
    ADD CONSTRAINT quality_legal_unit_establishment_stat_statistical_unit_fkey
        FOREIGN KEY (unit_type, unit_id, PERIOD valid_range)
        REFERENCES public.statistical_unit (unit_type, unit_id, PERIOD valid_range) NOT ENFORCED;
COMMENT ON CONSTRAINT quality_legal_unit_establishment_stat_statistical_unit_fkey ON public.quality_legal_unit_establishment_stat IS
  'NOT ENFORCED: names the statistical_unit row for readers and for PostgREST''s embed (statistical_unit?select=*,quality_legal_unit_establishment_stat!inner()); derive rewrites statistical_unit freely and the next worker.derive_quality makes this table right again. statistical_unit_refresh and reset name this table in their TRUNCATE.';
COMMENT ON TABLE public.quality_establishment_activity_differs IS
  'Findings of check 4, establishment_activity_differs (h9mhxe): one row per legal unit''s statistical_unit row whose primary establishment has another primary activity category than the legal unit. Filled from public.quality_establishment_activity_differs_def by public.quality_relation_derive per hash partition in worker.derive_quality.';
COMMENT ON TABLE public.quality_legal_unit_establishment_stat IS
  'Findings of the per-variable checks establishments_above_legal_unit and legal_unit_above_establishments (h9mhxe): one row per check (a rule and summed variable) and legal unit''s statistical_unit row it lists, with the comparison that decided it. One table serves both rules for every variable because they share one comparison. Filled from public.quality_legal_unit_establishment_stat_def by public.quality_relation_derive per hash partition in worker.derive_quality.';

CREATE VIEW public.quality_establishment_activity_differs_def WITH (security_invoker = on) AS
SELECT 4 AS check_id,
       su.unit_type, su.unit_id, su.valid_range,
       public.existence_from(su) AS existence_from, public.existence_until(su) AS existence_until,
       su.hash_slot,
       te.unit_id AS primary_establishment_id,
       su.primary_activity_category_id AS legal_unit_activity_category_id,
       te.primary_activity_category_id AS establishment_activity_category_id
FROM public.statistical_unit AS su
JOIN public.timeline_establishment AS te
  ON te.legal_unit_id = su.unit_id AND te.primary_for_legal_unit
 AND te.valid_from <= su.valid_from AND su.valid_from < te.valid_until
WHERE su.unit_type = 'legal_unit'
  AND su.primary_activity_category_id IS DISTINCT FROM te.primary_activity_category_id;
COMMENT ON VIEW public.quality_establishment_activity_differs_def IS
  'The rule of check 4, establishment_activity_differs (xz3jej): a legal unit''s statistical_unit row whose primary establishment, at the row''s start, has another primary activity category (either may have none). Its columns are those of public.quality_establishment_activity_differs, which public.quality_relation_derive fills from it per hash partition.';

CREATE VIEW public.quality_legal_unit_establishment_stat_def WITH (security_invoker = on) AS
SELECT qc.id AS check_id,
       c.unit_type, c.unit_id, daterange(c.valid_from, c.valid_until) AS valid_range,
       public.unit_existence_from(su.valid_from, su.birth_date) AS existence_from,
       public.unit_existence_until(su.valid_until, su.death_date) AS existence_until,
       c.hash_slot,
       sd.id AS stat_definition_id,
       c.legal_unit_value, c.establishments_sum, c.establishment_count::integer AS establishment_count
FROM public.legal_unit_establishment_stat_comparison AS c
JOIN public.stat_definition AS sd ON sd.code = c.stat_code
JOIN public.statistical_unit AS su
  ON su.unit_type = c.unit_type AND su.unit_id = c.unit_id AND su.valid_from = c.valid_from AND su.hash_slot = c.hash_slot
JOIN public.quality_check AS qc
  ON qc.stat_definition_id = sd.id
 AND ((qc.rule = 'establishments_above_legal_unit' AND c.legal_unit_value < c.establishments_sum)
   OR (qc.rule = 'legal_unit_above_establishments' AND c.establishments_sum < c.legal_unit_value
       AND c.establishments_with_value = c.establishment_count));
COMMENT ON VIEW public.quality_legal_unit_establishment_stat_def IS
  'The rules of the per-variable checks (ca6dk5) on public.legal_unit_establishment_stat_comparison: establishments_above_legal_unit when the counted establishments'' sum is above the legal unit''s own value, legal_unit_above_establishments when the own value is above the sum while every counted establishment has a value. One row per check and legal unit row; its columns are those of public.quality_legal_unit_establishment_stat, which public.quality_relation_derive fills from it per hash partition.';
GRANT SELECT ON public.quality_establishment_activity_differs_def TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.quality_legal_unit_establishment_stat_def TO authenticated, regular_user, admin_user;

CREATE FUNCTION public.quality_relation_derive(p_hash_slots int4range)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $quality_relation_derive$
DECLARE
    -- Explicit half-open bounds, so the btree indexes on hash_slot are used (as in
    -- worker.derive_statistical_unit_facet_partition).
    v_from integer := lower(p_hash_slots);
    v_until integer := upper(p_hash_slots);
    v_findings jsonb;
BEGIN
    DELETE FROM public.quality_establishment_activity_differs
     WHERE hash_slot >= v_from AND hash_slot < v_until;
    DELETE FROM public.quality_legal_unit_establishment_stat
     WHERE hash_slot >= v_from AND hash_slot < v_until;

    WITH activity_differs AS (
        INSERT INTO public.quality_establishment_activity_differs
            (check_id, unit_type, unit_id, valid_range, existence_from, existence_until,
             primary_establishment_id, legal_unit_activity_category_id, establishment_activity_category_id)
        SELECT d.check_id, d.unit_type, d.unit_id, d.valid_range, d.existence_from, d.existence_until,
               d.primary_establishment_id, d.legal_unit_activity_category_id, d.establishment_activity_category_id
        FROM public.quality_establishment_activity_differs_def AS d
        WHERE d.hash_slot >= v_from AND d.hash_slot < v_until
        RETURNING check_id
    ), establishment_stat AS (
        INSERT INTO public.quality_legal_unit_establishment_stat
            (check_id, unit_type, unit_id, valid_range, existence_from, existence_until,
             stat_definition_id, legal_unit_value, establishments_sum, establishment_count)
        SELECT s.check_id, s.unit_type, s.unit_id, s.valid_range, s.existence_from, s.existence_until,
               s.stat_definition_id, s.legal_unit_value, s.establishments_sum, s.establishment_count
        FROM public.quality_legal_unit_establishment_stat_def AS s
        WHERE s.hash_slot >= v_from AND s.hash_slot < v_until
        RETURNING check_id
    ), inserted AS (
        SELECT check_id FROM activity_differs
        UNION ALL
        SELECT check_id FROM establishment_stat
    )
    SELECT jsonb_object_agg(k.check_key, k.findings) INTO v_findings
    FROM (
        SELECT CASE WHEN sd.code IS NULL THEN qc.rule::text ELSE qc.rule::text || ':' || sd.code END AS check_key,
               count(*) AS findings
        FROM inserted AS i
        JOIN public.quality_check AS qc ON qc.id = i.check_id
        LEFT JOIN public.stat_definition AS sd ON sd.id = qc.stat_definition_id
        GROUP BY 1
    ) AS k;
    RETURN COALESCE(v_findings, '{}'::jsonb);
END;
$quality_relation_derive$;
COMMENT ON FUNCTION public.quality_relation_derive(int4range) IS
  'Rederives the relation checks'' findings of one range of hash slots (0pn35h, h9mhxe): empties both relation tables in the range and fills them from their _def views. Returns the findings per check written, keyed by rule and, for a per-variable check, rule:code. Called per partition by worker.derive_quality_partition. Row checks need no derive: statistical_unit.quality_check_ids is generated from the row.';

CREATE FUNCTION public.quality_relation_derive()
 RETURNS jsonb
 LANGUAGE sql
AS $quality_relation_derive$
    SELECT public.quality_relation_derive(int4range(0, 16384));
$quality_relation_derive$;
COMMENT ON FUNCTION public.quality_relation_derive() IS
  'Rederives every relation check''s findings: public.quality_relation_derive over all hash slots. For tests and repair; the worker derives per partition.';

CREATE OR REPLACE PROCEDURE worker.derive_quality_partition(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    -- The relation findings per check in this partition, one number per check, so the parent's info
    -- sums them over its children (worker.complete_parent_if_ready).
    p_info := public.quality_relation_derive((payload->>'hash_partition')::int4range);
END;
$procedure$;

CREATE OR REPLACE PROCEDURE worker.derive_quality(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_task_id bigint;
    v_hash_partition_size integer := GREATEST(1, 16384 / public.get_partition_count_target());
    -- A full run: one range per analytics worker, so each does one large pass (fewer tasks than the
    -- small partitions, which cost a task's start and commit each).
    v_full_partition_size integer := 16384 / GREATEST(1, (SELECT q.default_concurrency FROM worker.queue_registry AS q WHERE q.queue = 'analytics'));
    v_full boolean;
    v_hash_partition int4range;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    -- Every partition on a full recalculation (valid_from -infinity and valid_until infinity, see
    -- worker.enqueue_derive_statistical_unit_all; a full statistical_unit refresh empties the
    -- relation tables). Otherwise the partitions holding a changed unit: the cycle's changed units'
    -- hash slots, recorded by worker.derive_statistical_unit and cleared by
    -- worker.statistical_history_facet_delta_reduce after this step.
    v_full := v_valid_from = '-infinity'::date AND v_valid_until = 'infinity'::date;

    FOR v_hash_partition IN
        SELECT int4range(p.start, LEAST(p.start + v_full_partition_size, 16384))
        FROM generate_series(0, 16383, v_full_partition_size) AS p(start)
        WHERE v_full
        UNION
        SELECT int4range((d.dirty_hash_slot / v_hash_partition_size) * v_hash_partition_size,
                         LEAST((d.dirty_hash_slot / v_hash_partition_size) * v_hash_partition_size + v_hash_partition_size, 16384))
        FROM public.statistical_unit_facet_dirty_hash_slots AS d
        WHERE NOT v_full
        ORDER BY 1
    LOOP
        PERFORM worker.spawn(
            p_command => 'derive_quality_partition',
            p_payload => jsonb_build_object('command', 'derive_quality_partition', 'hash_partition', v_hash_partition::text),
            p_parent_id => v_task_id
        );
        v_child_count := v_child_count + 1;
    END LOOP;

    p_info := jsonb_build_object('child_count', v_child_count, 'full', v_full);
END;
$procedure$;

DROP FUNCTION public.quality_finding_derive();
DROP FUNCTION public.quality_finding_derive(int4range);
DROP VIEW public.quality_finding_def;
DROP TABLE public.quality_finding;

COMMENT ON PROCEDURE worker.derive_quality_partition(jsonb, jsonb) IS
  'A child of worker.derive_quality: rederives the relation checks'' findings of one hash partition (public.quality_relation_derive), concurrently with its siblings (0pn35h). SECURITY DEFINER: it writes the RLS-protected relation tables.';

-- ######## readers ########
CREATE FUNCTION public.statistical_unit_quality(quality_check_id integer, valid_on date)
 RETURNS SETOF public.statistical_unit
 LANGUAGE sql
 STABLE
AS $statistical_unit_quality$
    -- A row check: the units whose generated quality_check_ids holds it (GIN, gin__int_ops).
    SELECT su.*
    FROM public.statistical_unit AS su
    WHERE su.quality_check_ids @> ARRAY[statistical_unit_quality.quality_check_id]
      AND public.existence_from(su) <= statistical_unit_quality.valid_on
      AND statistical_unit_quality.valid_on < public.existence_until(su)
      AND EXISTS (SELECT 1 FROM public.quality_check AS qc
                  WHERE qc.id = statistical_unit_quality.quality_check_id AND qc.kind = 'row')
    UNION ALL
    -- A relation check: the legal unit rows its table lists at the instant, then those rows.
    SELECT su.*
    FROM (
        SELECT d.unit_type, d.unit_id, d.valid_range
        FROM public.quality_establishment_activity_differs AS d
        WHERE d.check_id = statistical_unit_quality.quality_check_id
          AND d.existence_from <= statistical_unit_quality.valid_on AND statistical_unit_quality.valid_on < d.existence_until
        UNION ALL
        SELECT s.unit_type, s.unit_id, s.valid_range
        FROM public.quality_legal_unit_establishment_stat AS s
        JOIN public.quality_check AS qc ON qc.id = s.check_id AND public.in_use(qc)
        WHERE s.check_id = statistical_unit_quality.quality_check_id
          AND s.existence_from <= statistical_unit_quality.valid_on AND statistical_unit_quality.valid_on < s.existence_until
    ) AS f
    JOIN public.statistical_unit AS su
      ON su.unit_type = f.unit_type AND su.unit_id = f.unit_id AND su.valid_range = f.valid_range
$statistical_unit_quality$;
COMMENT ON FUNCTION public.statistical_unit_quality(integer, date) IS
  'The statistical_unit rows one data-quality check (public.quality_check.id) lists at valid_on, for the search when the check lists few units (app/src/app/search/quality-search.ts): it starts from the check''s store, a row check''s GIN index on quality_check_ids or a relation check''s table, and so finds a rare check''s units at once, where the planner cannot estimate a rare array element and walks the sort index. A per-variable check whose variable is not in use (public.in_use) lists nothing (bxt67q). The search''s other filters, order and paging apply to the rows returned.';
GRANT EXECUTE ON FUNCTION public.statistical_unit_quality(integer, date) TO authenticated, regular_user, admin_user;

CREATE FUNCTION public.quality_check_count(valid_on date)
 RETURNS TABLE (check_id integer, units bigint)
 LANGUAGE sql
 STABLE
AS $quality_check_count$
    -- Row checks: one grouped count over the rows that have a check (the partial covering index
    -- idx_statistical_unit_quality_check_count), split per id afterwards.
    WITH by_array AS (
        SELECT su.quality_check_ids, count(*) AS units
        FROM public.statistical_unit AS su
        WHERE su.quality_check_ids <> '{}'
          AND public.existence_from(su) <= quality_check_count.valid_on
          AND quality_check_count.valid_on < public.existence_until(su)
        GROUP BY su.quality_check_ids
    ), counted AS (
        SELECT r.check_id, sum(a.units)::bigint AS units
        FROM by_array AS a CROSS JOIN LATERAL unnest(a.quality_check_ids) AS r(check_id)
        GROUP BY r.check_id
        UNION ALL
        SELECT d.check_id, count(*)
        FROM public.quality_establishment_activity_differs AS d
        WHERE d.existence_from <= quality_check_count.valid_on AND quality_check_count.valid_on < d.existence_until
        GROUP BY d.check_id
        UNION ALL
        SELECT s.check_id, count(*)
        FROM public.quality_legal_unit_establishment_stat AS s
        WHERE s.existence_from <= quality_check_count.valid_on AND quality_check_count.valid_on < s.existence_until
        GROUP BY s.check_id
    )
    SELECT qc.id, COALESCE(c.units, 0)
    FROM public.quality_check AS qc
    LEFT JOIN counted AS c ON c.check_id = qc.id
    WHERE public.in_use(qc)
$quality_check_count$;
COMMENT ON FUNCTION public.quality_check_count(date) IS
  'The number of statistical_unit rows each check in use (public.in_use) lists at valid_on, 0 for none: the dashboard''s Data quality cards and the search''s choice of path (quality-search.ts). Row checks are counted in one grouped pass over quality_check_ids, relation checks from their tables, all by the rows'' existence dates (lib/unit-existence.ts).';
GRANT EXECUTE ON FUNCTION public.quality_check_count(date) TO authenticated, regular_user, admin_user;

-- ######## refresh, reset, RLS ########
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
        latitude, longitude, altitude, domestic,
        postal_address_part1, postal_address_part2, postal_address_part3, postal_postcode, postal_postplace,
        postal_region_id, postal_region_path, postal_region_code, postal_country_id, postal_country_iso_2,
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

        -- The relation tables point at the rows replaced here and are refilled by the next
        -- worker.derive_quality. They reference statistical_unit by NOT ENFORCED foreign keys,
        -- which TRUNCATE refuses without CASCADE even with all three tables listed.
        TRUNCATE public.statistical_unit, public.quality_establishment_activity_differs,
                 public.quality_legal_unit_establishment_stat CASCADE;
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
$procedure$;

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

        -- statistical_unit is emptied together with the relation check tables, which reference it
        -- by NOT ENFORCED foreign keys: TRUNCATE refuses such a key without CASCADE, even with the
        -- tables listed. CASCADE is kept to this statement so that a new enforced key to any table
        -- in the list below still stops reset instead of emptying its table.
        TRUNCATE public.statistical_unit, public.quality_establishment_activity_differs,
                 public.quality_legal_unit_establishment_stat CASCADE;

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
            public.quality_establishment_activity_differs,
            public.quality_legal_unit_establishment_stat,
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

    CASE WHEN scope = 'customisation' THEN
        -- quality_check.switched_on: the starting set again, as shipped (public.quality_check_starting_set).
        WITH switched AS (
            UPDATE public.quality_check AS qc
            SET switched_on = (qc.stat_definition_id IS NULL
                               AND qc.rule IN (SELECT s.rule FROM public.quality_check_starting_set() AS s(rule)))
            WHERE qc.switched_on IS DISTINCT FROM (qc.stat_definition_id IS NULL
                               AND qc.rule IN (SELECT s.rule FROM public.quality_check_starting_set() AS s(rule)))
            RETURNING qc.switched_on
        )
        SELECT jsonb_build_object('quality_check', jsonb_build_object(
                   'switched_on_count', count(*) FILTER (WHERE switched_on),
                   'switched_off_count', count(*) FILTER (WHERE NOT switched_on)))
        FROM switched INTO changed;
        result := result || changed;
    ELSE END CASE;

    RETURN result;
END;
$function$;

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
    PERFORM admin.add_rls_regular_user_can_read('public.quality_check'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_establishment_activity_differs'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_legal_unit_establishment_stat'::regclass);
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
$function$;

-- The relation tables start empty: a full derive fills them after the upgrade (its quality step
-- runs every partition). One pending full derive is kept (worker.enqueue_derive_statistical_unit_all),
-- so this shares the one the counting migration (20261127161312) asks for; a database without
-- units schedules nothing.
SELECT worker.enqueue_derive_statistical_unit_all();

END;
