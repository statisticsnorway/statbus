-- Migration 20261118151709: reset scopes follow the dialog and restore factory defaults (50bwaz)
--
-- The reset dialog's three choices are the three scopes of public.reset:
--   units           the statistical units and the import jobs that made them
--   getting-started units + the Getting started steps: settings (country and
--                   activity category standard), custom activity codes,
--                   regions and custom region versions, custom sectors and
--                   custom legal forms; the activity category standards are
--                   restored as shipped
--   customisation   getting-started + the /admin Customisation section: the
--                   system rows of each table are restored from
--                   <table>_factory_default and custom rows removed; users
--                   are never touched
-- <table>_factory_default holds the rows as shipped, the one source both a
-- fresh install and reset use. System priorities start at 10 in steps of 10
-- so 1-9 are free for users, and a priority is unique among enabled rows.
BEGIN;

-- ---------------------------------------------------------------------
-- Factory defaults: the rows as shipped, one table per customisable table.
-- Read-only through the API for every role: they change only with a
-- release (a migration), so a reset always has the shipped values.
-- ---------------------------------------------------------------------
CREATE TABLE public.activity_category_standard_factory_default (
    code character varying(16) PRIMARY KEY,
    name character varying NOT NULL,
    description character varying NOT NULL,
    code_pattern public.activity_category_code_behaviour NOT NULL,
    enabled boolean NOT NULL,
    lasts_to date
);
COMMENT ON TABLE public.activity_category_standard_factory_default IS
  'The public.activity_category_standard rows as shipped with StatBus. public.reset (scope getting-started) restores the system rows of public.activity_category_standard to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.activity_category_standard_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.activity_category_standard_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY activity_category_standard_factory_default_authenticated_read ON public.activity_category_standard_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY activity_category_standard_factory_default_regular_user_read ON public.activity_category_standard_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY activity_category_standard_factory_default_admin_user_read ON public.activity_category_standard_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.activity_category_standard_factory_default(code, name, description, code_pattern, enabled, lasts_to) VALUES
    ('isic_v4', 'ISIC 4', 'ISIC Version 4', 'digits', true, NULL),
    ('nace_v2.1', 'NACE 2.1', 'NACE Version 2 Revision 1', 'dot_after_two_digits', true, NULL);

CREATE TABLE public.sector_factory_default (
    path public.ltree PRIMARY KEY,
    name text NOT NULL
);
COMMENT ON TABLE public.sector_factory_default IS
  'The public.sector rows as shipped with StatBus. public.reset (scope getting-started) restores the system rows of public.sector to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.sector_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.sector_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY sector_factory_default_authenticated_read ON public.sector_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY sector_factory_default_regular_user_read ON public.sector_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY sector_factory_default_admin_user_read ON public.sector_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.sector_factory_default(path, name) VALUES
    ('domestic', 'Domestic sectors'),
    ('r_of_world', 'Rest of the world'),
    ('domestic.a_non_fin', 'Non-financial corporations'),
    ('domestic.b_fin', 'Financial corporations'),
    ('domestic.c_pub_sector', 'General government'),
    ('domestic.d_nonprofit', 'Non-profit institutions serving households'),
    ('domestic.e_household', 'Households'),
    ('r_of_world.f_foreign', 'Rest of the world'),
    ('domestic.a_non_fin.1110', 'Public unincorporated enterprises, owned by central government'),
    ('domestic.a_non_fin.1120', 'Public incorporated enterprises, owned by central government'),
    ('domestic.a_non_fin.1510', 'Public unincorporated enterprises, owned by local government'),
    ('domestic.a_non_fin.1520', 'Public incorporated enterprises, owned by local government'),
    ('domestic.a_non_fin.2100', 'Private non-financial incorporated enterprises'),
    ('domestic.a_non_fin.2300', 'Private non-financial unincorporated enterprises'),
    ('domestic.a_non_fin.2500', 'Private non-profit institutions serving enterprises'),
    ('domestic.a_non_fin.2700', 'Private for-profit Schools'),
    ('domestic.b_fin.3100', 'Central Bank'),
    ('domestic.b_fin.3200', 'Banks'),
    ('domestic.b_fin.3500', 'Mortgage companies'),
    ('domestic.b_fin.3600', 'Finance companies'),
    ('domestic.b_fin.3900', 'State lending institutions etc.'),
    ('domestic.b_fin.4100', 'Financial holding companies'),
    ('domestic.b_fin.4300', 'Mutual funds'),
    ('domestic.b_fin.4500', 'Investment trusts and private equity funds'),
    ('domestic.b_fin.4900', 'Other financial enterprises, except insurance companies and pension funds'),
    ('domestic.b_fin.5500', 'Life insurance companies and pension funds'),
    ('domestic.b_fin.5700', 'Non-life insurance companies'),
    ('domestic.c_pub_sector.6100', 'Central government'),
    ('domestic.c_pub_sector.6500', 'Local government'),
    ('domestic.c_pub_sector.6700', 'Public Schools'),
    ('domestic.d_nonprofit.7000', 'Non-profit institutions serving households'),
    ('domestic.d_nonprofit.7700', 'Private non-profit Schools'),
    ('domestic.e_household.8200', 'Unincorporated enterprises within households'),
    ('domestic.e_household.8300', 'Housing cooperatives etc.'),
    ('domestic.e_household.8500', 'Employees, recipients of property income, pensions and social contributions, students etc.'),
    ('r_of_world.f_foreign.9000', 'Rest of the world');

CREATE TABLE public.legal_form_factory_default (
    code text PRIMARY KEY,
    name text NOT NULL
);
COMMENT ON TABLE public.legal_form_factory_default IS
  'The public.legal_form rows as shipped with StatBus. public.reset (scope getting-started) restores the system rows of public.legal_form to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.legal_form_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.legal_form_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY legal_form_factory_default_authenticated_read ON public.legal_form_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY legal_form_factory_default_regular_user_read ON public.legal_form_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY legal_form_factory_default_admin_user_read ON public.legal_form_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.legal_form_factory_default(code, name) VALUES
    ('ACO', 'Association/club/organisation'),
    ('AUPS', 'Administrative Unit - Public Sector'),
    ('BE', 'Bankrupt estate'),
    ('CFO', 'Condominium flat owner'),
    ('CMBE', 'County municipal business enterprise'),
    ('COOP', 'Co-operation'),
    ('CTY', 'County'),
    ('DDRG', 'Dominant Domestic Religious Group'),
    ('RG', 'Religious Group'),
    ('DFBE', 'Domestic Division of Foreign Business Enterprise'),
    ('EEEG', 'European Economic Enterprise Group'),
    ('FDN', 'Foundation'),
    ('FE', 'Foreign entity'),
    ('GP', 'General partnership'),
    ('GPSL', 'General partnership with shared liability'),
    ('HBC', 'House building cooperative'),
    ('HC', 'Housing cooperative'),
    ('IAR', 'Individuals who are registered in affiliated register'),
    ('IMC', 'Inter-municipal company'),
    ('IRAU', 'Individuals Registered in the Auditor Register'),
    ('JO', 'Joint office'),
    ('JOLP', 'Joint ownership according to the law of property'),
    ('JOSC', 'Jointly owned shipping company'),
    ('LC', 'Limited company'),
    ('LLC', 'Company with limited liability'),
    ('LP', 'Limited partnership'),
    ('MBE', 'Municipal business enterprise'),
    ('MIC', 'Mutual insurance company'),
    ('MUN', 'Municipality'),
    ('OBC', 'Other body corporate'),
    ('OBE', 'Other business enterprise in accordance with special legislation'),
    ('OE', 'Other estates'),
    ('ONBC', 'Other non-body corporate'),
    ('OS', 'Organisation section'),
    ('PC', 'Public corporation'),
    ('PF', 'Pension Fund'),
    ('PLC', 'Public limited company'),
    ('SB', 'Savings bank'),
    ('SCPA', 'Subsidiary to Commercial and Public Administration'),
    ('SE', 'European Company'),
    ('SP', 'Sole proprietorship'),
    ('SSU', 'Specially sectioned unit'),
    ('STATE', 'State'),
    ('UNDEF', 'Undefined'),
    ('UT', 'Unit trusts'),
    ('VATRL', 'Compulsory registration in the Value Added Tax Registration List');

CREATE TABLE public.unit_size_factory_default (
    code text PRIMARY KEY,
    name text NOT NULL
);
COMMENT ON TABLE public.unit_size_factory_default IS
  'The public.unit_size rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.unit_size to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.unit_size_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.unit_size_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY unit_size_factory_default_authenticated_read ON public.unit_size_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY unit_size_factory_default_regular_user_read ON public.unit_size_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY unit_size_factory_default_admin_user_read ON public.unit_size_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.unit_size_factory_default(code, name) VALUES
    ('tny', 'Tiny'),
    ('sml', 'Small'),
    ('med', 'Medium'),
    ('lrg', 'Large');

CREATE TABLE public.data_source_factory_default (
    code text PRIMARY KEY,
    name text NOT NULL
);
COMMENT ON TABLE public.data_source_factory_default IS
  'The public.data_source rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.data_source to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.data_source_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.data_source_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY data_source_factory_default_authenticated_read ON public.data_source_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY data_source_factory_default_regular_user_read ON public.data_source_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY data_source_factory_default_admin_user_read ON public.data_source_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.data_source_factory_default(code, name) VALUES
    ('ntr', 'National Tax Registry'),
    ('nlr', 'National Legal Business Registry'),
    ('census', 'Census'),
    ('survey', 'Survey Data'),
    ('mi', 'Manual Input'),
    ('other', 'Other External Data Source');

CREATE TABLE public.foreign_participation_factory_default (
    code text PRIMARY KEY,
    name text NOT NULL
);
COMMENT ON TABLE public.foreign_participation_factory_default IS
  'The public.foreign_participation rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.foreign_participation to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.foreign_participation_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.foreign_participation_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY foreign_participation_factory_default_authenticated_read ON public.foreign_participation_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY foreign_participation_factory_default_regular_user_read ON public.foreign_participation_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY foreign_participation_factory_default_admin_user_read ON public.foreign_participation_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.foreign_participation_factory_default(code, name) VALUES
    ('a', 'Exports or imports of goods'),
    ('b', 'Exports or imports of services'),
    ('c', 'Merchanting'),
    ('d', 'Equity Investments abroad'),
    ('e', 'Non -Equity (External borrowing or lending)'),
    ('f', 'External Remittances'),
    ('g', 'No foreign participation'),
    ('h', 'Multiple kinds of foreign participation. See notes');

CREATE TABLE public.power_group_type_factory_default (
    code text PRIMARY KEY,
    name text NOT NULL
);
COMMENT ON TABLE public.power_group_type_factory_default IS
  'The public.power_group_type rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.power_group_type to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.power_group_type_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.power_group_type_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY power_group_type_factory_default_authenticated_read ON public.power_group_type_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY power_group_type_factory_default_regular_user_read ON public.power_group_type_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY power_group_type_factory_default_admin_user_read ON public.power_group_type_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.power_group_type_factory_default(code, name) VALUES
    ('dcn', 'Domestically Controlled National'),
    ('fcn', 'Foreign Controlled National'),
    ('dcm', 'Domestically Controlled Multinational'),
    ('fcm', 'Foreign Controlled Multinational');

CREATE TABLE public.legal_reorg_type_factory_default (
    code text PRIMARY KEY,
    name text NOT NULL,
    description text NOT NULL
);
COMMENT ON TABLE public.legal_reorg_type_factory_default IS
  'The public.legal_reorg_type rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.legal_reorg_type to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.legal_reorg_type_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.legal_reorg_type_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY legal_reorg_type_factory_default_authenticated_read ON public.legal_reorg_type_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY legal_reorg_type_factory_default_regular_user_read ON public.legal_reorg_type_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY legal_reorg_type_factory_default_admin_user_read ON public.legal_reorg_type_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.legal_reorg_type_factory_default(code, name, description) VALUES
    ('acq', 'Acquisition', 'A corporate action where one company takes over controlling interest in another company. The acquired company may continue to operate as an independent entity.'),
    ('div', 'Divestiture', 'The process of selling off a portion of a company, such as a subsidiary, department, or property, often to streamline operations or raise capital.'),
    ('mer', 'Merger', 'A process where two or more companies combine to form a new entity, often to achieve synergies, expand market reach, or enhance capabilities.'),
    ('reb', 'Re-branding', 'The process of changing the corporate image of a company, including changes to logos, marketing materials, and overall brand strategy, to create a new identity.'),
    ('res', 'Restructuring', 'A significant modification in the organization, strategy, or operations of a company, often in response to financial instability, market changes, or management decisions.'),
    ('spo', 'Spin-off', 'A type of corporate reorganization where a company creates a new independent company through the sale or distribution of new shares of an existing business/division.');

CREATE TABLE public.legal_rel_type_factory_default (
    code text PRIMARY KEY,
    name text NOT NULL,
    description text NOT NULL,
    primary_influencer_only boolean NOT NULL
);
COMMENT ON TABLE public.legal_rel_type_factory_default IS
  'The public.legal_rel_type rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.legal_rel_type to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.legal_rel_type_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.legal_rel_type_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY legal_rel_type_factory_default_authenticated_read ON public.legal_rel_type_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY legal_rel_type_factory_default_regular_user_read ON public.legal_rel_type_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY legal_rel_type_factory_default_admin_user_read ON public.legal_rel_type_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.legal_rel_type_factory_default(code, name, description, primary_influencer_only) VALUES
    ('ownership', 'Ownership', 'Direct share ownership percentage', false),
    ('control', 'Control', 'Controlling interest (may differ from ownership via voting rights or agreements)', true);

CREATE TABLE public.status_factory_default (
    code character varying PRIMARY KEY,
    name text NOT NULL,
    assigned_by_default boolean NOT NULL,
    used_for_counting boolean NOT NULL,
    priority integer NOT NULL
);
COMMENT ON TABLE public.status_factory_default IS
  'The public.status rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.status to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.status_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.status_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY status_factory_default_authenticated_read ON public.status_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY status_factory_default_regular_user_read ON public.status_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY status_factory_default_admin_user_read ON public.status_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.status_factory_default(code, name, assigned_by_default, used_for_counting, priority) VALUES
    ('active', 'Active', true, true, 10),
    ('passive', 'Passive', false, false, 20);

CREATE TABLE public.stat_definition_factory_default (
    code character varying PRIMARY KEY,
    type public.stat_type NOT NULL,
    frequency public.stat_frequency NOT NULL,
    name character varying NOT NULL,
    description text,
    priority integer NOT NULL,
    enabled boolean NOT NULL
);
COMMENT ON TABLE public.stat_definition_factory_default IS
  'The public.stat_definition rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.stat_definition to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.stat_definition_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.stat_definition_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY stat_definition_factory_default_authenticated_read ON public.stat_definition_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY stat_definition_factory_default_regular_user_read ON public.stat_definition_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY stat_definition_factory_default_admin_user_read ON public.stat_definition_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.stat_definition_factory_default(code, type, frequency, name, description, priority, enabled) VALUES
    ('employees', 'int', 'yearly', 'Employees', 'The number of people receiving an official salary with government reporting.', 10, true),
    ('turnover', 'float', 'yearly', 'Turnover', 'The amount (Local Currency)', 20, true);

CREATE TABLE public.external_ident_type_factory_default (
    code character varying(128) PRIMARY KEY,
    name character varying(50) NOT NULL,
    description text,
    priority integer NOT NULL,
    enabled boolean NOT NULL
);
COMMENT ON TABLE public.external_ident_type_factory_default IS
  'The public.external_ident_type rows as shipped with StatBus. public.reset (scope customisation) restores the system rows of public.external_ident_type to exactly these values, undoing edits; reset never changes this table.';
ALTER TABLE public.external_ident_type_factory_default ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.external_ident_type_factory_default TO authenticated, regular_user, admin_user;
CREATE POLICY external_ident_type_factory_default_authenticated_read ON public.external_ident_type_factory_default FOR SELECT TO authenticated USING (true);
CREATE POLICY external_ident_type_factory_default_regular_user_read ON public.external_ident_type_factory_default FOR SELECT TO regular_user USING (true);
CREATE POLICY external_ident_type_factory_default_admin_user_read ON public.external_ident_type_factory_default FOR SELECT TO admin_user USING (true);

INSERT INTO public.external_ident_type_factory_default(code, name, description, priority, enabled) VALUES
    ('tax_ident', 'Tax Identifier', 'Stable and country unique identifier used for tax reporting.', 10, true),
    ('stat_ident', 'Statistical Identifier', 'Stable identifier generated by Statbus', 20, true),
    ('person_ident', 'Person Identifier', 'Personal identification number (national ID, passport, etc.)', 30, false);

-- ---------------------------------------------------------------------
-- Priority: unique among enabled rows only, so a disabled row keeps its
-- number. An installation's enabled duplicates (custom/ma.sql gives two
-- statuses priority 3 and two priority 4) are renumbered deterministically,
-- by priority then code, keeping their order.
-- ---------------------------------------------------------------------
ALTER TABLE public.external_ident_type DROP CONSTRAINT external_ident_type_priority_key;
ALTER TABLE public.stat_definition DROP CONSTRAINT stat_definition_priority_key;

-- Shipped system rows still at their old shipped priority move to the new
-- one; a priority the user chose is kept.
UPDATE public.external_ident_type AS eit SET priority = fd.priority
  FROM public.external_ident_type_factory_default AS fd,
       (VALUES ('tax_ident', 1), ('stat_ident', 2), ('person_ident', 10)) AS old(code, priority)
 WHERE eit.code = fd.code AND eit.code = old.code AND eit.priority = old.priority;
UPDATE public.stat_definition AS sd SET priority = fd.priority
  FROM public.stat_definition_factory_default AS fd,
       (VALUES ('employees', 1), ('turnover', 2)) AS old(code, priority)
 WHERE sd.code = fd.code AND sd.code = old.code AND sd.priority = old.priority;
UPDATE public.status AS s SET priority = fd.priority
  FROM public.status_factory_default AS fd,
       (VALUES ('active', 1), ('passive', 2)) AS old(code, priority)
 WHERE NOT s.custom AND s.code = fd.code AND s.code = old.code AND s.priority = old.priority;
-- person_ident ships disabled (since 20260326160507 on fresh installs);
-- an installation still at the old shipped state follows.
UPDATE public.external_ident_type AS eit SET enabled = false
 WHERE eit.code = 'person_ident' AND eit.enabled
   AND NOT EXISTS (SELECT 1 FROM public.external_ident AS ei WHERE ei.type_id = eit.id);

WITH ranked AS (
    SELECT s.id, s.priority,
           s.priority + (row_number() OVER (PARTITION BY s.priority ORDER BY s.code) - 1) AS wanted
      FROM public.status AS s WHERE s.enabled
), clashing AS (
    SELECT r.id, (SELECT max(priority) FROM public.status WHERE enabled) + row_number() OVER (ORDER BY r.priority, r.id) AS new_priority
      FROM ranked AS r WHERE r.wanted <> r.priority
)
UPDATE public.status AS s SET priority = c.new_priority FROM clashing AS c WHERE s.id = c.id;

CREATE UNIQUE INDEX external_ident_type_enabled_priority_key ON public.external_ident_type(priority) WHERE enabled;
CREATE UNIQUE INDEX stat_definition_enabled_priority_key ON public.stat_definition(priority) WHERE enabled;
CREATE UNIQUE INDEX status_enabled_priority_key ON public.status(priority) WHERE enabled;
COMMENT ON INDEX public.external_ident_type_enabled_priority_key IS 'Priority orders the enabled identifiers; a disabled one keeps its number without blocking it. System rows start at 10 so 1-9 are free for users.';
COMMENT ON INDEX public.stat_definition_enabled_priority_key IS 'Priority orders the enabled statistical variables; a disabled one keeps its number without blocking it. System rows start at 10 so 1-9 are free for users.';
COMMENT ON INDEX public.status_enabled_priority_key IS 'Priority orders the enabled statuses; a disabled one keeps its number without blocking it. System rows start at 10 so 1-9 are free for users.';

-- ---------------------------------------------------------------------
-- The three scopes the reset dialog names.
-- ---------------------------------------------------------------------
DROP FUNCTION public.reset(boolean, public.reset_scope);
DROP TYPE public.reset_scope;
CREATE TYPE public.reset_scope AS ENUM ('units', 'getting-started', 'customisation');
COMMENT ON TYPE public.reset_scope IS
  'What public.reset empties, each scope including the one before: units = the statistical units and the import jobs that made them; getting-started = units + the Getting started steps (settings, custom activity codes, regions, custom sectors, custom legal forms) with the activity category standards as shipped; customisation = getting-started + the /admin Customisation section restored to its factory defaults. Users are never touched.';

CREATE FUNCTION public.reset(confirmed boolean, scope public.reset_scope)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $reset$
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

        -- statistical_unit is emptied together with quality_establishment_activity_differs, which
        -- references it by a NOT ENFORCED foreign key: TRUNCATE refuses such a key without CASCADE,
        -- even with both tables listed. CASCADE is kept to this statement so that a new enforced
        -- key to any table in the list below still stops reset instead of emptying its table.
        TRUNCATE public.statistical_unit, public.quality_establishment_activity_differs CASCADE;

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
$reset$;
COMMENT ON FUNCTION public.reset(boolean, public.reset_scope) IS
  'Empties what the reset dialog names; see public.reset_scope. Shipped rows are restored from the <table>_factory_default tables.';

END;
