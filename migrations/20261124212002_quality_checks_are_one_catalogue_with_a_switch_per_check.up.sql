-- Migration 20261124212002: quality checks are one catalogue with a switch per check (05pe0x).
--
-- Every data-quality check is a rule (public.quality_rule) and, for a rule that compares a
-- summed statistical variable, that variable. The list of checks is a view over the rules and
-- the enabled summed variables, so it follows the variables by itself; an installation switches
-- a check off with a row in public.quality_check_switched_off (every check starts on).
-- The units a check lists are rows of one table, public.quality_finding, filled by
-- worker.derive_quality after each recalculation. It replaces the table per check:
--   quality_establishment_activity_differs  (migration 20261118134950)
--   quality_establishments_above_legal_unit and quality_legal_unit_above_establishments
--                                           (migration 20261124115435)
-- and adds the rules the dashboard counted from statistical_unit columns (missing region,
-- missing activity category, missing physical location). Each finding carries its
-- statistical_unit row's existence dates, so one grouped query counts every check at an instant.
-- The search lists a check's units through public.statistical_unit_quality(), which starts from
-- the findings.
BEGIN;

-- ######## the rules ########
CREATE TYPE public.quality_rule AS ENUM (
    'missing_region',
    'missing_activity_category',
    'missing_physical_location',
    'establishment_activity_differs',
    'establishments_above_legal_unit',
    'legal_unit_above_establishments'
);

COMMENT ON TYPE public.quality_rule IS
  'The kinds of data-quality check (05pe0x). missing_region: a legal unit or establishment located in the installation''s own country (settings.country_id) without a region (pkne34). missing_activity_category: a legal unit or establishment without a primary activity category. missing_physical_location: a legal unit or establishment without a physical location. establishment_activity_differs: a legal unit whose primary establishment has another primary activity category (xz3jej). establishments_above_legal_unit: a legal unit whose counted establishments'' values of a summed variable add up to more than its own value (ca6dk5). legal_unit_above_establishments: a legal unit whose own value of a summed variable is above its counted establishments'' sum while every one of them has a value (ca6dk5). The last two are a check per summed variable (public.quality_rule_per_stat). A new rule is a new value here with its rule in public.quality_finding_def; the app''s wording is keyed by this enum, so the type check fails until the rule has a name.';

CREATE FUNCTION public.quality_rule_per_stat(rule public.quality_rule)
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $quality_rule_per_stat$
    SELECT rule IN ('establishments_above_legal_unit', 'legal_unit_above_establishments')
$quality_rule_per_stat$;

COMMENT ON FUNCTION public.quality_rule_per_stat(public.quality_rule) IS
  'True when the rule is a check per summed statistical variable (stat_definition of type int or float): it is then always stored with that variable''s stat_definition_id, and every other rule without one (the CHECK constraints of quality_check_switched_off and quality_finding).';

-- ######## the switches ########
CREATE TABLE public.quality_check_switched_off (
    rule public.quality_rule NOT NULL,
    stat_definition_id integer REFERENCES public.stat_definition (id) ON DELETE CASCADE,
    CONSTRAINT quality_check_switched_off_key UNIQUE NULLS NOT DISTINCT (rule, stat_definition_id),
    CONSTRAINT quality_check_switched_off_variable_matches_rule
        CHECK (public.quality_rule_per_stat(rule) = (stat_definition_id IS NOT NULL))
);

COMMENT ON TABLE public.quality_check_switched_off IS
  'The checks an installation has switched off (05pe0x): hidden from the dashboard''s Data quality section and the search''s Quality filter. Only switched-off checks are stored, so every check, a new variable''s checks too, starts on. A disabled variable keeps its row for when it is enabled again; deleting the variable deletes it. Written by admins on Admin > Data quality checks; reset''s customisation scope empties it.';
COMMENT ON COLUMN public.quality_check_switched_off.stat_definition_id IS
  'The summed variable of a per-variable rule (public.quality_rule_per_stat); NULL for every other rule.';
COMMENT ON CONSTRAINT quality_check_switched_off_key ON public.quality_check_switched_off IS
  'A check is switched off once: the rule and its variable, NULL counting as a value (NULLS NOT DISTINCT), so a rule without a variable has one row at most.';
COMMENT ON CONSTRAINT quality_check_switched_off_variable_matches_rule ON public.quality_check_switched_off IS
  'A per-variable rule names its variable and every other rule names none (public.quality_rule_per_stat), so each row is a check of public.quality_check.';

-- Everyone signed in reads the switches (the dashboard and the Quality filter); admins write them.
SELECT admin.add_rls_regular_user_can_read('public.quality_check_switched_off'::regclass);

-- ######## the checks ########
CREATE VIEW public.quality_check
WITH (security_invoker = on) AS
WITH check_of AS (
    SELECT r.rule, NULL::integer AS stat_definition_id, 0 AS stat_priority
    FROM unnest(enum_range(NULL::public.quality_rule)) AS r(rule)
    WHERE NOT public.quality_rule_per_stat(r.rule)
    UNION ALL
    SELECT r.rule, sd.id, sd.priority
    FROM unnest(enum_range(NULL::public.quality_rule)) AS r(rule)
    JOIN public.stat_definition AS sd
      ON sd.enabled AND sd.type IN ('int', 'float')
    WHERE public.quality_rule_per_stat(r.rule)
)
SELECT c.rule,
       c.stat_definition_id,
       NOT EXISTS (
           SELECT 1 FROM public.quality_check_switched_off AS qs
           WHERE qs.rule = c.rule
             AND COALESCE(qs.stat_definition_id, 0) = COALESCE(c.stat_definition_id, 0)
       ) AS on_dashboard,
       row_number() OVER (ORDER BY c.rule, c.stat_priority, c.stat_definition_id) AS priority
FROM check_of AS c;

COMMENT ON VIEW public.quality_check IS
  'Every data-quality check of this installation (05pe0x): each rule that is not per variable once, and each per-variable rule once per enabled summed statistical variable (stat_definition of type int or float), so adding, disabling or enabling a variable adds or removes its checks with no other step. on_dashboard is false when the check is in public.quality_check_switched_off. priority orders the checks: by rule (the enum''s order), then by the variable''s priority. The dashboard and the search''s Quality filter show the checks with on_dashboard; Admin > Data quality checks lists them all.';
GRANT SELECT ON public.quality_check TO authenticated, regular_user, admin_user;

-- ######## the findings ########
CREATE TABLE public.quality_finding (
    rule public.quality_rule NOT NULL,
    stat_definition_id integer REFERENCES public.stat_definition (id) ON DELETE CASCADE,
    unit_type public.statistical_unit_type NOT NULL,
    unit_id integer NOT NULL,
    valid_from date NOT NULL,
    valid_until date NOT NULL,
    valid_range daterange NOT NULL GENERATED ALWAYS AS (daterange(valid_from, valid_until)) STORED,
    existence_from date NOT NULL,
    existence_until date NOT NULL,
    detail jsonb,
    CONSTRAINT quality_finding_key
        UNIQUE NULLS NOT DISTINCT (rule, stat_definition_id, unit_type, unit_id, valid_range),
    CONSTRAINT quality_finding_variable_matches_rule
        CHECK (public.quality_rule_per_stat(rule) = (stat_definition_id IS NOT NULL)),
    CONSTRAINT quality_finding_statistical_unit_fkey
        FOREIGN KEY (unit_type, unit_id, PERIOD valid_range)
        REFERENCES public.statistical_unit (unit_type, unit_id, PERIOD valid_range) NOT ENFORCED
);

COMMENT ON TABLE public.quality_finding IS
  'The units each data-quality check lists (05pe0x): one row per check (rule, and variable for a per-variable rule) and statistical_unit row it lists. Filled from public.quality_finding_def by public.quality_finding_derive() in worker.derive_quality after statistical_unit is published; it holds every check, switched off or not, so switching one on shows its number at once. The dashboard counts every check at an instant in one query on (rule, stat_definition_id, existence_from, existence_until); the search lists a check''s units through public.statistical_unit_quality().';
COMMENT ON COLUMN public.quality_finding.stat_definition_id IS
  'The summed variable a per-variable rule compares (public.quality_rule_per_stat); NULL for every other rule.';
COMMENT ON COLUMN public.quality_finding.valid_range IS
  'The statistical_unit row''s period; with unit_type and unit_id the key of that row.';
COMMENT ON COLUMN public.quality_finding.existence_from IS
  'public.existence_from of the statistical_unit row, copied so that a check is counted at an instant from this table alone (lib/unit-existence.ts: existence_from <= d < existence_until).';
COMMENT ON COLUMN public.quality_finding.existence_until IS
  'public.existence_until of the statistical_unit row; see existence_from.';
COMMENT ON COLUMN public.quality_finding.detail IS
  'What the rule compared, for a reader of the finding. establishments_above_legal_unit and legal_unit_above_establishments: {"legal_unit": own value, "establishments_sum": sum, "establishments": count}. establishment_activity_differs: {"legal_unit_activity_category_id", "primary_establishment_id", "primary_establishment_activity_category_id"}. NULL for the rules that say all in their name.';
COMMENT ON CONSTRAINT quality_finding_statistical_unit_fkey ON public.quality_finding IS
  'NOT ENFORCED: describes the link to the statistical_unit row for readers; derive rewrites statistical_unit freely and the next worker.derive_quality makes this table right again. A TRUNCATE of statistical_unit names this table and says CASCADE.';
COMMENT ON CONSTRAINT quality_finding_key ON public.quality_finding IS
  'A check lists a statistical_unit row once: the rule, its variable (NULL counting as a value), and the row''s unit and period; the key quality_finding_derive() merges on.';
COMMENT ON CONSTRAINT quality_finding_variable_matches_rule ON public.quality_finding IS
  'A per-variable rule''s finding names its variable and every other rule''s names none (public.quality_rule_per_stat).';

CREATE INDEX quality_finding_count_idx
    ON public.quality_finding (rule, (COALESCE(stat_definition_id, 0)), existence_from, existence_until);
COMMENT ON INDEX public.quality_finding_count_idx IS
  'Serves the dashboard''s count of every check at an instant and public.statistical_unit_quality(): a check (rule and variable, 0 for none) and the instant within the existence dates.';

SELECT admin.add_rls_regular_user_can_read('public.quality_finding'::regclass);

-- ######## the rules, as one view ########
-- The legal unit / establishment comparison (migration 20261124115435) stays as it is: both
-- per-variable rules read it.
COMMENT ON VIEW public.legal_unit_establishment_stat_comparison IS
  'Per legal_unit row of statistical_unit and enabled summed stat (int, float) held both by the legal unit and by at least one counted establishment: the legal unit''s own value (statistical_unit.stats) and its counted establishments'' count, count with a value, and sum at the row''s valid_from. The quality rules establishments_above_legal_unit and legal_unit_above_establishments read it (public.quality_finding_def); a legal unit''s total takes the larger level (public.jsonb_stats_covers).';
CREATE VIEW public.quality_finding_def
WITH (security_invoker = on) AS
SELECT 'missing_region'::public.quality_rule AS rule,
       NULL::integer AS stat_definition_id,
       su.unit_type, su.unit_id, su.valid_from, su.valid_until,
       NULL::jsonb AS detail
FROM public.statistical_unit AS su
WHERE su.unit_type IN ('legal_unit', 'establishment')
  AND su.domestic
  AND su.physical_country_id IS NOT NULL
  AND su.physical_region_path IS NULL
UNION ALL
SELECT 'missing_activity_category', NULL, su.unit_type, su.unit_id, su.valid_from, su.valid_until, NULL
FROM public.statistical_unit AS su
WHERE su.unit_type IN ('legal_unit', 'establishment')
  AND su.primary_activity_category_path IS NULL
UNION ALL
SELECT 'missing_physical_location', NULL, su.unit_type, su.unit_id, su.valid_from, su.valid_until, NULL
FROM public.statistical_unit AS su
WHERE su.unit_type IN ('legal_unit', 'establishment')
  AND su.physical_country_id IS NULL
UNION ALL
SELECT 'establishment_activity_differs', NULL, su.unit_type, su.unit_id, su.valid_from, su.valid_until,
       jsonb_build_object(
           'legal_unit_activity_category_id', su.primary_activity_category_id,
           'primary_establishment_id', te.unit_id,
           'primary_establishment_activity_category_id', te.primary_activity_category_id)
FROM public.statistical_unit AS su
JOIN public.timeline_establishment AS te
  ON te.legal_unit_id = su.unit_id
 AND te.primary_for_legal_unit
 AND te.valid_from <= su.valid_from AND su.valid_from < te.valid_until
WHERE su.unit_type = 'legal_unit'
  AND su.primary_activity_category_id IS DISTINCT FROM te.primary_activity_category_id
UNION ALL
SELECT 'establishments_above_legal_unit', sd.id, c.unit_type, c.unit_id, c.valid_from, c.valid_until,
       jsonb_build_object('legal_unit', c.legal_unit_value,
                          'establishments_sum', c.establishments_sum,
                          'establishments', c.establishment_count)
FROM public.legal_unit_establishment_stat_comparison AS c
JOIN public.stat_definition AS sd ON sd.code = c.stat_code
WHERE c.legal_unit_value < c.establishments_sum
UNION ALL
SELECT 'legal_unit_above_establishments', sd.id, c.unit_type, c.unit_id, c.valid_from, c.valid_until,
       jsonb_build_object('legal_unit', c.legal_unit_value,
                          'establishments_sum', c.establishments_sum,
                          'establishments', c.establishment_count)
FROM public.legal_unit_establishment_stat_comparison AS c
JOIN public.stat_definition AS sd ON sd.code = c.stat_code
WHERE c.establishments_sum < c.legal_unit_value
  AND c.establishments_with_value = c.establishment_count;

COMMENT ON VIEW public.quality_finding_def IS
  'The rule of every data-quality check (public.quality_rule), read from the published statistical_unit and the legal unit / establishment comparison; public.quality_finding_derive() makes public.quality_finding equal to it. Missing region counts only units located in the installation''s own country (domestic): a unit abroad has no region of this country to lack, and a unit without a physical location is missing_physical_location (pkne34).';
GRANT SELECT ON public.quality_finding_def TO authenticated, regular_user, admin_user;

CREATE FUNCTION public.quality_finding_derive()
RETURNS void
LANGUAGE plpgsql
AS $quality_finding_derive$
BEGIN
    RAISE DEBUG 'Running quality_finding_derive()';
    MERGE INTO public.quality_finding AS target
    USING (
        SELECT d.rule, d.stat_definition_id, d.unit_type, d.unit_id, d.valid_from, d.valid_until, d.detail,
               public.unit_existence_from(su.valid_from, su.birth_date) AS existence_from,
               public.unit_existence_until(su.valid_until, su.death_date) AS existence_until
        FROM public.quality_finding_def AS d
        JOIN public.statistical_unit AS su
          ON su.unit_type = d.unit_type AND su.unit_id = d.unit_id
         AND su.valid_range = daterange(d.valid_from, d.valid_until)
    ) AS source
    ON target.rule = source.rule
   AND COALESCE(target.stat_definition_id, 0) = COALESCE(source.stat_definition_id, 0)
   AND target.unit_type = source.unit_type
   AND target.unit_id = source.unit_id
   AND target.valid_range = daterange(source.valid_from, source.valid_until)
    WHEN MATCHED AND (target.detail IS DISTINCT FROM source.detail
                      OR target.existence_from IS DISTINCT FROM source.existence_from
                      OR target.existence_until IS DISTINCT FROM source.existence_until) THEN
        UPDATE SET detail = source.detail,
                   existence_from = source.existence_from,
                   existence_until = source.existence_until
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (rule, stat_definition_id, unit_type, unit_id, valid_from, valid_until, existence_from, existence_until, detail)
        VALUES (source.rule, source.stat_definition_id, source.unit_type, source.unit_id, source.valid_from,
                source.valid_until, source.existence_from, source.existence_until, source.detail)
    WHEN NOT MATCHED BY SOURCE THEN DELETE;
    ANALYZE public.quality_finding;
END;
$quality_finding_derive$;

COMMENT ON FUNCTION public.quality_finding_derive() IS
  'Makes public.quality_finding equal to public.quality_finding_def (insert, update, delete), with each finding''s existence dates from its statistical_unit row; called by worker.derive_quality.';

-- ######## the search lists a check's units ########
CREATE FUNCTION public.statistical_unit_quality(
    quality_rule public.quality_rule,
    valid_on date,
    quality_stat_definition_id integer DEFAULT NULL)
RETURNS SETOF public.statistical_unit
LANGUAGE sql
STABLE
AS $statistical_unit_quality$
    SELECT su.*
    FROM public.statistical_unit AS su
    WHERE public.existence_from(su) <= statistical_unit_quality.valid_on
      AND statistical_unit_quality.valid_on < public.existence_until(su)
      AND EXISTS (
          SELECT 1 FROM public.quality_finding AS f
          WHERE f.rule = statistical_unit_quality.quality_rule
            AND COALESCE(f.stat_definition_id, 0) = COALESCE(statistical_unit_quality.quality_stat_definition_id, 0)
            AND f.existence_from <= statistical_unit_quality.valid_on
            AND statistical_unit_quality.valid_on < f.existence_until
            AND f.unit_type = su.unit_type
            AND f.unit_id = su.unit_id
            AND f.valid_range = su.valid_range)
$statistical_unit_quality$;

COMMENT ON FUNCTION public.statistical_unit_quality(public.quality_rule, date, integer) IS
  'The statistical_unit rows that exist at valid_on and that a check (rule, and variable for a per-variable rule) lists, read from the findings first: the check, the instant (quality_finding_count_idx) and then each unit by its key. The search uses it for a check that lists few units at the time frame (Norway 2026-11-26: 2 units 9 ms, 17 units 36 ms for a page; about 0.16 ms per listed unit, so 161,571 units take 29 s), and walks statistical_unit in the page''s order with quality_finding as an inner embed for a check that lists many (161,571 units 0.1 s, 2 units 117 s): owner decision 2026-11-26, threshold 1,000 units by the check''s count at the time frame. Called as rpc/statistical_unit_quality with the page''s other filters, order and paging applied to its rows; its count equals the dashboard''s count of the check at valid_on.';
GRANT EXECUTE ON FUNCTION public.statistical_unit_quality(public.quality_rule, date, integer) TO authenticated, regular_user, admin_user;

-- ######## the reports phase's quality step fills the findings ########
-- Weight is seconds / 10 on the Norway register: about 30 s for every rule (prototype 16 s for
-- the statistical_unit rules, 14 s for the comparison).
UPDATE worker.pipeline_step_weight SET weight = 3 WHERE step = 'derive_quality';
CREATE OR REPLACE PROCEDURE worker.derive_quality(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
BEGIN
    PERFORM public.quality_finding_derive();

    p_info := (
        SELECT jsonb_build_object('findings', jsonb_object_agg(f.rule, f.findings))
        FROM (SELECT qf.rule, count(*) AS findings FROM public.quality_finding AS qf GROUP BY qf.rule) AS f
    );
END;
$procedure$;

-- ######## the old tables go ########
DROP FUNCTION public.quality_establishment_activity_differs_derive();
DROP FUNCTION public.quality_legal_unit_establishments_derive();
DROP VIEW public.quality_establishment_activity_differs_def;
DROP VIEW public.quality_establishments_above_legal_unit_def;
DROP VIEW public.quality_legal_unit_above_establishments_def;
DROP TABLE public.quality_establishment_activity_differs;
DROP TABLE public.quality_establishments_above_legal_unit;
DROP TABLE public.quality_legal_unit_above_establishments;

-- statistical_unit_refresh: the full refresh empties quality_finding with statistical_unit.
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

        -- quality_finding points at the rows replaced here and is refilled by the next
        -- worker.derive_quality. It references statistical_unit by a NOT ENFORCED foreign
        -- key, which TRUNCATE refuses without CASCADE even with both tables listed.
        TRUNCATE public.statistical_unit, public.quality_finding CASCADE;
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

-- reset: units scope empties quality_finding with statistical_unit; customisation scope switches every check on.
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

        -- statistical_unit is emptied together with public.quality_finding, which
        -- references it by a NOT ENFORCED foreign key: TRUNCATE refuses such a key without CASCADE,
        -- even with both tables listed. CASCADE is kept to this statement so that a new enforced
        -- key to any table in the list below still stops reset instead of emptying its table.
        TRUNCATE public.statistical_unit, public.quality_finding CASCADE;

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

    CASE WHEN scope = 'customisation' THEN
        -- quality_check_switched_off: every check switched on again, as shipped (it ships with no
        -- rows, so every row goes).
        WITH deleted AS (
            DELETE FROM public.quality_check_switched_off WHERE true
            RETURNING 1
        )
        SELECT jsonb_build_object('quality_check_switched_off', jsonb_build_object(
            'deleted_count', (SELECT count(*) FROM deleted)
        )) INTO changed;
        result := result || changed;
    ELSE END CASE;

    RETURN result;
END;
$function$
;

-- apply_rls_to_all_tables: quality_finding replaces the three quality tables.
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
    PERFORM admin.add_rls_regular_user_can_read('public.quality_finding'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_check_switched_off'::regclass);
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

-- The findings come from statistical_unit as it stands, which this migration does not change: an
-- installation with units gets one worker.derive_quality task (Norway: about 30 s) rather than a
-- full recalculation. An empty database (the seed and test template) gets none. derive_quality has
-- no enqueue function and no deduplication key: a second run beside a pipeline's own is harmless,
-- as quality_finding_derive() makes the table equal to its rules each time.
INSERT INTO worker.tasks (command, payload)
SELECT 'derive_quality', jsonb_build_object('command', 'derive_quality', 'valid_from', '-infinity', 'valid_until', 'infinity')
WHERE EXISTS (SELECT 1 FROM public.statistical_unit);
-- A queued task waits until the worker is told (as worker.enqueue_derive_statistical_unit_all does).
SELECT pg_notify('worker_tasks', 'analytics');

END;
