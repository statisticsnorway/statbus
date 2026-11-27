-- Migration 20261127091517: quality check catalogue with integer ids, relation tables and intarray gin indexes
-- me96tn, part 1 of h9mhxe (design report 0pn35h). Additive: statistical_unit's columns,
-- public.quality_finding_def, public.legal_unit_establishment_stat_comparison and worker.derive_quality
-- are unchanged; existing readers keep working.
BEGIN;

-- ######## int[] GIN indexes for intarray ########
-- The migrate runner installs intarray (cli/internal/migrate/extensions.go) before migrations run.
-- With intarray installed, integer[] && integer[] resolves to intarray's operator, which a GIN index
-- with the default array_ops does not serve: the Data source filter became a full scan. An index with
-- gin__int_ops serves it.
DROP INDEX public.idx_statistical_unit_data_source_ids;
CREATE INDEX idx_statistical_unit_data_source_ids ON public.statistical_unit USING GIN (data_source_ids public.gin__int_ops);
COMMENT ON INDEX public.idx_statistical_unit_data_source_ids IS 'Search filter: data source (data_source_ids overlaps ...).';

DROP INDEX public.idx_timeline_enterprise_related_establishment_ids;
CREATE INDEX idx_timeline_enterprise_related_establishment_ids ON public.timeline_enterprise USING GIN (related_establishment_ids public.gin__int_ops);
COMMENT ON INDEX public.idx_timeline_enterprise_related_establishment_ids IS
  'Containment and overlap lookups on related_establishment_ids; gin__int_ops because intarray''s integer[] operators are the ones such a lookup resolves to.';
DROP INDEX public.idx_timeline_enterprise_related_legal_unit_ids;
CREATE INDEX idx_timeline_enterprise_related_legal_unit_ids ON public.timeline_enterprise USING GIN (related_legal_unit_ids public.gin__int_ops);
COMMENT ON INDEX public.idx_timeline_enterprise_related_legal_unit_ids IS
  'Containment and overlap lookups on related_legal_unit_ids; gin__int_ops because intarray''s integer[] operators are the ones such a lookup resolves to.';
DROP INDEX public.idx_timeline_legal_unit_related_establishment_ids;
CREATE INDEX idx_timeline_legal_unit_related_establishment_ids ON public.timeline_legal_unit USING GIN (related_establishment_ids public.gin__int_ops);
COMMENT ON INDEX public.idx_timeline_legal_unit_related_establishment_ids IS
  'Containment and overlap lookups on related_establishment_ids; gin__int_ops because intarray''s integer[] operators are the ones such a lookup resolves to.';

-- The function that recreates statistical_unit's indexes builds the data source index the same way.
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

-- ######## the check catalogue ########
CREATE TYPE public.quality_check_kind AS ENUM ('row', 'relation');
COMMENT ON TYPE public.quality_check_kind IS
  'Where a data-quality check''s findings are stored (h9mhxe). row: the unit''s own statistical_unit row decides the check (missing region, missing activity category, missing physical location, secondary activity equals primary). relation: the unit and other units decide it (a legal unit and its establishments), stored in a table per kind of relation (public.quality_establishment_activity_differs, public.quality_legal_unit_establishment_stat).';

CREATE FUNCTION public.quality_rule_kind(rule public.quality_rule)
 RETURNS public.quality_check_kind
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
AS $quality_rule_kind$
    SELECT CASE WHEN rule IN ('establishment_activity_differs', 'establishments_above_legal_unit', 'legal_unit_above_establishments')
                THEN 'relation'::public.quality_check_kind
                ELSE 'row'::public.quality_check_kind
           END
$quality_rule_kind$;
COMMENT ON FUNCTION public.quality_rule_kind(public.quality_rule) IS
  'The kind of a rule''s checks (public.quality_check_kind): relation for the rules that compare a legal unit with its establishments, row for the rules a statistical_unit row decides alone. A new rule is given its kind here.';

CREATE TABLE public.quality_check_catalogue (
    id integer GENERATED BY DEFAULT AS IDENTITY (START WITH 101) PRIMARY KEY,
    rule public.quality_rule NOT NULL,
    stat_definition_id integer REFERENCES public.stat_definition(id) ON DELETE CASCADE,
    kind public.quality_check_kind NOT NULL,
    priority integer NOT NULL,
    CONSTRAINT quality_check_catalogue_rule_variable_key UNIQUE NULLS NOT DISTINCT (rule, stat_definition_id),
    CONSTRAINT quality_check_catalogue_id_variable_key UNIQUE (id, stat_definition_id),
    CONSTRAINT quality_check_catalogue_variable_matches_rule CHECK (public.quality_rule_per_stat(rule) = (stat_definition_id IS NOT NULL)),
    CONSTRAINT quality_check_catalogue_kind_matches_rule CHECK (kind = public.quality_rule_kind(rule))
);
COMMENT ON TABLE public.quality_check_catalogue IS
  'Every data-quality check of this installation with its integer id (h9mhxe): each rule that is not per variable once, with a fixed id (1 missing_region, 2 missing_activity_category, 3 missing_physical_location, 4 establishment_activity_differs, 7 secondary_activity_equals_primary), and each per-variable rule once per summed variable (stat_definition of type int or float), with an id from 101 up given when the variable is created and kept by the stat_definition lifecycle callback (public.quality_check_catalogue_generate / _cleanup). The id is what findings store (an int[] on statistical_unit for row checks, check_id in the relation tables); it is never reused, so a stored id always names the same check. Part 2 of h9mhxe replaces the public.quality_check view with this table under that name.';
COMMENT ON COLUMN public.quality_check_catalogue.id IS
  'The check''s number in findings. Fixed for the checks that are not per variable; from the identity (101 up) for a per-variable check; never reused after a check is removed.';
COMMENT ON COLUMN public.quality_check_catalogue.rule IS
  'The check''s rule, the slug the app''s wording is keyed by (public.quality_rule).';
COMMENT ON COLUMN public.quality_check_catalogue.stat_definition_id IS
  'The summed variable a per-variable rule compares (public.quality_rule_per_stat); NULL for every other rule. Deleting the variable deletes its checks.';
COMMENT ON COLUMN public.quality_check_catalogue.kind IS
  'Where the check''s findings are stored (public.quality_check_kind), as public.quality_rule_kind gives for the rule.';
COMMENT ON COLUMN public.quality_check_catalogue.priority IS
  'The dashboard order of the check, lowest first: the rule''s position in public.quality_rule times 1000 plus the variable''s stat_definition.priority, so the checks of a rule stay together in variable order.';
COMMENT ON CONSTRAINT quality_check_catalogue_rule_variable_key ON public.quality_check_catalogue IS
  'A check is a rule and its variable (NULL counting as a value): it is in the catalogue once.';
COMMENT ON CONSTRAINT quality_check_catalogue_id_variable_key ON public.quality_check_catalogue IS
  'Target of public.quality_legal_unit_establishment_stat''s (check_id, stat_definition_id) foreign key, so a comparison''s variable is its check''s variable.';
COMMENT ON CONSTRAINT quality_check_catalogue_variable_matches_rule ON public.quality_check_catalogue IS
  'A per-variable check names its variable and every other check names none (public.quality_rule_per_stat).';
COMMENT ON CONSTRAINT quality_check_catalogue_kind_matches_rule ON public.quality_check_catalogue IS
  'A check''s kind is its rule''s kind (public.quality_rule_kind).';

INSERT INTO public.quality_check_catalogue (id, rule, stat_definition_id, kind, priority)
SELECT v.id, v.rule, NULL, public.quality_rule_kind(v.rule), array_position(enum_range(NULL::public.quality_rule), v.rule) * 1000
FROM (VALUES (1, 'missing_region'::public.quality_rule),
             (2, 'missing_activity_category'),
             (3, 'missing_physical_location'),
             (4, 'establishment_activity_differs'),
             (7, 'secondary_activity_equals_primary')) AS v(id, rule);

CREATE PROCEDURE public.quality_check_catalogue_generate()
 LANGUAGE plpgsql
AS $quality_check_catalogue_generate$
BEGIN
    -- One check per per-variable rule and summed variable; an existing check keeps its id and
    -- follows its variable's priority. Ids come in rule then variable order, so a replay gives
    -- the same ids. Only missing checks are inserted: an INSERT ... ON CONFLICT would draw an id
    -- for every existing check on every call.
    UPDATE public.quality_check_catalogue AS qc
    SET priority = array_position(enum_range(NULL::public.quality_rule), qc.rule) * 1000 + sd.priority
    FROM public.stat_definition AS sd
    WHERE qc.stat_definition_id = sd.id
      AND qc.priority <> array_position(enum_range(NULL::public.quality_rule), qc.rule) * 1000 + sd.priority;

    INSERT INTO public.quality_check_catalogue (rule, stat_definition_id, kind, priority)
    SELECT r.rule, sd.id, public.quality_rule_kind(r.rule),
           array_position(enum_range(NULL::public.quality_rule), r.rule) * 1000 + sd.priority
    FROM unnest(enum_range(NULL::public.quality_rule)) AS r(rule)
    JOIN public.stat_definition AS sd ON sd.type IN ('int', 'float')
    WHERE public.quality_rule_per_stat(r.rule)
      AND NOT EXISTS (
          SELECT FROM public.quality_check_catalogue AS qc
          WHERE qc.rule = r.rule AND qc.stat_definition_id = sd.id)
    ORDER BY r.rule, sd.priority, sd.id;
END;
$quality_check_catalogue_generate$;
COMMENT ON PROCEDURE public.quality_check_catalogue_generate() IS
  'stat_definition lifecycle callback (label quality_check_catalogue): gives every summed variable (type int or float) its per-variable checks in public.quality_check_catalogue, with new ids, and keeps their priority in step with the variable''s. A disabled variable keeps its checks and ids; readers count only enabled variables.';

CREATE PROCEDURE public.quality_check_catalogue_cleanup()
 LANGUAGE plpgsql
AS $quality_check_catalogue_cleanup$
BEGIN
    -- A deleted variable's checks went with it (ON DELETE CASCADE); a variable that is no longer
    -- summed loses its checks here.
    DELETE FROM public.quality_check_catalogue AS qc
    USING public.stat_definition AS sd
    WHERE qc.stat_definition_id = sd.id
      AND sd.type NOT IN ('int', 'float');
END;
$quality_check_catalogue_cleanup$;
COMMENT ON PROCEDURE public.quality_check_catalogue_cleanup() IS
  'stat_definition lifecycle callback (label quality_check_catalogue): removes the per-variable checks of a variable whose type is no longer int or float. Their ids are not reused.';

CALL lifecycle_callbacks.add(
    label => 'quality_check_catalogue',
    table_names => ARRAY['public.stat_definition']::regclass[],
    generate_procedure => 'public.quality_check_catalogue_generate',
    cleanup_procedure => 'public.quality_check_catalogue_cleanup'
);
CALL public.quality_check_catalogue_generate();

-- ######## relation findings: a table per kind of relation ########
-- The relation tables carry the statistical_unit row key without a foreign key to it: statistical_unit
-- is emptied by TRUNCATE ... CASCADE in public.statistical_unit_refresh, which part 2 of h9mhxe
-- extends with these tables when it fills them. public.reset empties them with the units.
CREATE TABLE public.quality_establishment_activity_differs (
    check_id integer NOT NULL REFERENCES public.quality_check_catalogue(id) ON DELETE CASCADE,
    unit_type public.statistical_unit_type NOT NULL,
    unit_id integer NOT NULL,
    valid_range daterange NOT NULL,
    existence_from date NOT NULL,
    existence_until date NOT NULL,
    hash_slot integer GENERATED ALWAYS AS (public.hash_slot(unit_type, unit_id)) STORED,
    primary_establishment_id integer NOT NULL,
    legal_unit_activity_category_id integer NOT NULL REFERENCES public.activity_category(id) ON DELETE CASCADE,
    establishment_activity_category_id integer NOT NULL REFERENCES public.activity_category(id) ON DELETE CASCADE,
    CONSTRAINT quality_establishment_activity_differs_pkey PRIMARY KEY (check_id, unit_type, unit_id, valid_range),
    CONSTRAINT quality_establishment_activity_differs_is_its_check CHECK (check_id = 4),
    CONSTRAINT quality_activity_differs_primary_establishment_fkey
        FOREIGN KEY (primary_establishment_id, PERIOD valid_range)
        REFERENCES public.establishment (id, PERIOD valid_range) NOT ENFORCED
);
COMMENT ON TABLE public.quality_establishment_activity_differs IS
  'Findings of check 4, establishment_activity_differs (h9mhxe): one row per legal unit''s statistical_unit row whose primary establishment has another primary activity category than the legal unit. Filled by the relation step of worker.derive_quality (part 2 of h9mhxe); empty until then.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.check_id IS 'The check (public.quality_check_catalogue), always 4.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.unit_type IS 'The legal unit''s statistical_unit row key: unit_type (always legal_unit), unit_id and valid_range.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.unit_id IS 'The legal unit; see unit_type.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.valid_range IS 'The statistical_unit row''s period; see unit_type.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.existence_from IS
  'public.existence_from of the statistical_unit row, copied so that a check is counted at an instant from this table alone (lib/unit-existence.ts: existence_from <= d < existence_until).';
COMMENT ON COLUMN public.quality_establishment_activity_differs.existence_until IS 'public.existence_until of the statistical_unit row; see existence_from.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.hash_slot IS 'The unit''s public.hash_slot, the partition the relation step rederives the finding in (0pn35h).';
COMMENT ON COLUMN public.quality_establishment_activity_differs.primary_establishment_id IS 'The legal unit''s primary establishment over the row''s period.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.legal_unit_activity_category_id IS 'The legal unit''s primary activity category.';
COMMENT ON COLUMN public.quality_establishment_activity_differs.establishment_activity_category_id IS 'The primary establishment''s primary activity category, which differs from the legal unit''s.';
COMMENT ON CONSTRAINT quality_establishment_activity_differs_pkey ON public.quality_establishment_activity_differs IS
  'A check lists a statistical_unit row once; the key the relation step merges on.';
COMMENT ON CONSTRAINT quality_establishment_activity_differs_is_its_check ON public.quality_establishment_activity_differs IS
  'This table holds check 4 only: its columns are that check''s comparison.';
COMMENT ON CONSTRAINT quality_activity_differs_primary_establishment_fkey ON public.quality_establishment_activity_differs IS
  'NOT ENFORCED: describes the link to the primary establishment over the row''s period; edits of establishments are not held back by findings, and the next worker.derive_quality makes this table right again.';
CREATE INDEX quality_establishment_activity_differs_hash_slot_idx ON public.quality_establishment_activity_differs (hash_slot);
COMMENT ON INDEX public.quality_establishment_activity_differs_hash_slot_idx IS 'Serves the relation step''s rederive of one hash partition.';
CREATE INDEX quality_establishment_activity_differs_count_idx ON public.quality_establishment_activity_differs (check_id, existence_from, existence_until);
COMMENT ON INDEX public.quality_establishment_activity_differs_count_idx IS 'Serves the dashboard''s count of the check at an instant within the existence dates.';
CREATE INDEX quality_activity_differs_primary_establishment_idx ON public.quality_establishment_activity_differs (primary_establishment_id);
COMMENT ON INDEX public.quality_activity_differs_primary_establishment_idx IS 'Serves lookups of the findings that name an establishment.';
CREATE INDEX quality_establishment_activity_differs_lu_activity_idx ON public.quality_establishment_activity_differs (legal_unit_activity_category_id);
COMMENT ON INDEX public.quality_establishment_activity_differs_lu_activity_idx IS 'Serves the foreign key to activity_category on delete.';
CREATE INDEX quality_establishment_activity_differs_es_activity_idx ON public.quality_establishment_activity_differs (establishment_activity_category_id);
COMMENT ON INDEX public.quality_establishment_activity_differs_es_activity_idx IS 'Serves the foreign key to activity_category on delete.';

CREATE TABLE public.quality_legal_unit_establishment_stat (
    check_id integer NOT NULL,
    unit_type public.statistical_unit_type NOT NULL,
    unit_id integer NOT NULL,
    valid_range daterange NOT NULL,
    existence_from date NOT NULL,
    existence_until date NOT NULL,
    hash_slot integer GENERATED ALWAYS AS (public.hash_slot(unit_type, unit_id)) STORED,
    stat_definition_id integer NOT NULL REFERENCES public.stat_definition(id) ON DELETE CASCADE,
    legal_unit_value numeric,
    establishments_sum numeric,
    establishment_count integer NOT NULL,
    CONSTRAINT quality_legal_unit_establishment_stat_pkey PRIMARY KEY (check_id, unit_type, unit_id, valid_range),
    CONSTRAINT quality_legal_unit_establishment_stat_check_fkey
        FOREIGN KEY (check_id, stat_definition_id)
        REFERENCES public.quality_check_catalogue (id, stat_definition_id) ON DELETE CASCADE
);
COMMENT ON TABLE public.quality_legal_unit_establishment_stat IS
  'Findings of the per-variable checks establishments_above_legal_unit and legal_unit_above_establishments (h9mhxe): one row per check (a rule and summed variable) and legal unit''s statistical_unit row it lists, with the comparison that decided it. One table serves both rules for every variable because they share one comparison. Filled by the relation step of worker.derive_quality (part 2 of h9mhxe); empty until then.';
COMMENT ON COLUMN public.quality_legal_unit_establishment_stat.check_id IS 'The check (public.quality_check_catalogue): which rule, for the variable in stat_definition_id.';
COMMENT ON COLUMN public.quality_legal_unit_establishment_stat.unit_type IS 'The legal unit''s statistical_unit row key: unit_type (always legal_unit), unit_id and valid_range.';
COMMENT ON COLUMN public.quality_legal_unit_establishment_stat.unit_id IS 'The legal unit; see unit_type.';
COMMENT ON COLUMN public.quality_legal_unit_establishment_stat.valid_range IS 'The statistical_unit row''s period; see unit_type.';
COMMENT ON COLUMN public.quality_legal_unit_establishment_stat.existence_from IS
  'public.existence_from of the statistical_unit row, copied so that a check is counted at an instant from this table alone (lib/unit-existence.ts: existence_from <= d < existence_until).';
COMMENT ON COLUMN public.quality_legal_unit_establishment_stat.existence_until IS 'public.existence_until of the statistical_unit row; see existence_from.';
COMMENT ON COLUMN public.quality_legal_unit_establishment_stat.hash_slot IS 'The unit''s public.hash_slot, the partition the relation step rederives the finding in (0pn35h).';
COMMENT ON COLUMN public.quality_legal_unit_establishment_stat.stat_definition_id IS 'The summed variable compared; the check''s own variable (quality_legal_unit_establishment_stat_check_fkey).';
COMMENT ON COLUMN public.quality_legal_unit_establishment_stat.legal_unit_value IS 'The legal unit''s own value of the variable.';
COMMENT ON COLUMN public.quality_legal_unit_establishment_stat.establishments_sum IS 'The sum of the variable over the legal unit''s counted establishments.';
COMMENT ON COLUMN public.quality_legal_unit_establishment_stat.establishment_count IS 'How many counted establishments the sum is over.';
COMMENT ON CONSTRAINT quality_legal_unit_establishment_stat_pkey ON public.quality_legal_unit_establishment_stat IS
  'A check lists a statistical_unit row once; the key the relation step merges on.';
COMMENT ON CONSTRAINT quality_legal_unit_establishment_stat_check_fkey ON public.quality_legal_unit_establishment_stat IS
  'The check exists and its variable is the row''s variable; removing the check removes its findings.';
CREATE INDEX quality_legal_unit_establishment_stat_hash_slot_idx ON public.quality_legal_unit_establishment_stat (hash_slot);
COMMENT ON INDEX public.quality_legal_unit_establishment_stat_hash_slot_idx IS 'Serves the relation step''s rederive of one hash partition.';
CREATE INDEX quality_legal_unit_establishment_stat_count_idx ON public.quality_legal_unit_establishment_stat (check_id, existence_from, existence_until);
COMMENT ON INDEX public.quality_legal_unit_establishment_stat_count_idx IS 'Serves the dashboard''s count of each check at an instant within the existence dates.';
CREATE INDEX quality_legal_unit_establishment_stat_stat_definition_idx ON public.quality_legal_unit_establishment_stat (stat_definition_id);
COMMENT ON INDEX public.quality_legal_unit_establishment_stat_stat_definition_idx IS 'Serves the foreign key to stat_definition on delete.';

SELECT admin.add_rls_regular_user_can_read('public.quality_check_catalogue'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.quality_establishment_activity_differs'::regclass);
SELECT admin.add_rls_regular_user_can_read('public.quality_legal_unit_establishment_stat'::regclass);

-- apply_rls_to_all_tables: the three new tables.
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
    PERFORM admin.add_rls_regular_user_can_read('public.quality_check_switched_on'::regclass);
    PERFORM admin.add_rls_regular_user_can_read('public.quality_check_catalogue'::regclass);
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

-- reset: the relation findings are emptied with the units they name (their establishment key
-- refuses a TRUNCATE of establishment alone).
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
        -- quality_check_switched_on: the starting set again, as shipped (public.quality_check_starting_set).
        WITH deleted AS (
            DELETE FROM public.quality_check_switched_on WHERE true -- every row: the starting set is inserted below
            RETURNING 1
        )
        SELECT jsonb_build_object('deleted_count', count(*)) FROM deleted INTO changed;
        WITH inserted AS (
            INSERT INTO public.quality_check_switched_on (rule, stat_definition_id)
            SELECT s.rule, NULL FROM public.quality_check_starting_set() AS s(rule)
            RETURNING 1
        )
        SELECT jsonb_build_object('quality_check_switched_on',
                   changed || jsonb_build_object('inserted_count', count(*)))
        FROM inserted INTO changed;
        result := result || changed;
    ELSE END CASE;

    RETURN result;
END;
$function$;

END;
