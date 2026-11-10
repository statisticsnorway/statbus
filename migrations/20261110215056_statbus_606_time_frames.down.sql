-- STATBUS-606 down: restore time contexts as released in v2026.11.3.
-- Object definitions are the release-migrated database's pg_dump; the rows of
-- relative_period are its data. Job idents go back: live -> r_year_curr,
-- prev -> r_year_prev (y_YYYY is the same in both).
BEGIN;

-- 1. Jobs and their snapshot key go back first, while time_frame still exists.
ALTER TABLE public.import_job DROP CONSTRAINT job_parameters_must_match_valid_time_from_mode;

UPDATE public.import_job SET time_frame_ident = 'r_year_curr' WHERE time_frame_ident = 'live';
UPDATE public.import_job SET time_frame_ident = 'r_year_prev' WHERE time_frame_ident = 'prev';

UPDATE public.import_job
SET definition_snapshot = (definition_snapshot - 'time_frame')
    || jsonb_build_object('time_context', definition_snapshot->'time_frame')
WHERE definition_snapshot ? 'time_frame';

ALTER TABLE public.import_job RENAME COLUMN time_frame_ident TO time_context_ident;
COMMENT ON COLUMN public.import_job.time_context_ident IS NULL;

-- 2. The frames go.
DROP VIEW public.time_frame;
DROP TYPE public.time_frame_kind;

-- 3. The released types, table, rows and views come back.
CREATE TYPE public.relative_period_code AS ENUM (
    'today',
    'year_curr',
    'year_prev',
    'year_curr_only',
    'year_prev_only',
    'start_of_week_curr',
    'stop_of_week_prev',
    'start_of_week_prev',
    'start_of_month_curr',
    'stop_of_month_prev',
    'start_of_month_prev',
    'start_of_quarter_curr',
    'stop_of_quarter_prev',
    'start_of_quarter_prev',
    'start_of_semester_curr',
    'stop_of_semester_prev',
    'start_of_semester_prev',
    'start_of_year_curr',
    'stop_of_year_prev',
    'start_of_year_prev',
    'start_of_quinquennial_curr',
    'stop_of_quinquennial_prev',
    'start_of_quinquennial_prev',
    'start_of_decade_curr',
    'stop_of_decade_prev',
    'start_of_decade_prev'
);
CREATE TYPE public.relative_period_scope AS ENUM (
    'input_and_query',
    'query',
    'input'
);
CREATE TYPE public.time_context_type AS ENUM (
    'relative_period',
    'tag',
    'year'
);

\restrict KLxi7bOfxIqiBYdhKz8ZCHGOJ1jlDSTVc5Za2K4QuMrbg0lPADcTGknIxBTccnw
CREATE TABLE public.relative_period (
    id integer NOT NULL,
    code public.relative_period_code NOT NULL,
    name_when_query character varying(256),
    name_when_input character varying(256),
    scope public.relative_period_scope NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    CONSTRAINT "scope input_and_query requires name_when_input" CHECK (
CASE scope
    WHEN 'input_and_query'::public.relative_period_scope THEN ((name_when_input IS NOT NULL) AND (name_when_query IS NOT NULL))
    WHEN 'query'::public.relative_period_scope THEN ((name_when_input IS NULL) AND (name_when_query IS NOT NULL))
    WHEN 'input'::public.relative_period_scope THEN ((name_when_input IS NOT NULL) AND (name_when_query IS NULL))
    ELSE NULL::boolean
END)
);
ALTER TABLE public.relative_period ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.relative_period_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
CREATE VIEW public.relative_period_with_time WITH (security_invoker='on') AS
 WITH base_periods AS (
         SELECT relative_period.id,
            relative_period.code,
            relative_period.name_when_query,
            relative_period.name_when_input,
            relative_period.scope,
            relative_period.enabled,
            (
                CASE relative_period.code
                    WHEN 'today'::public.relative_period_code THEN (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone
                    WHEN 'year_prev'::public.relative_period_code THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone) - '1 day'::interval)
                    WHEN 'year_prev_only'::public.relative_period_code THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone) - '1 day'::interval)
                    WHEN 'year_curr'::public.relative_period_code THEN (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone
                    WHEN 'year_curr_only'::public.relative_period_code THEN (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone
                    WHEN 'start_of_week_curr'::public.relative_period_code THEN date_trunc('week'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone)
                    WHEN 'stop_of_week_prev'::public.relative_period_code THEN (date_trunc('week'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone) - '1 day'::interval)
                    WHEN 'start_of_week_prev'::public.relative_period_code THEN (date_trunc('week'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - '7 days'::interval)))::timestamp with time zone
                    WHEN 'start_of_month_curr'::public.relative_period_code THEN date_trunc('month'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone)
                    WHEN 'stop_of_month_prev'::public.relative_period_code THEN (date_trunc('month'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone) - '1 day'::interval)
                    WHEN 'start_of_month_prev'::public.relative_period_code THEN (date_trunc('month'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - '1 mon'::interval)))::timestamp with time zone
                    WHEN 'start_of_quarter_curr'::public.relative_period_code THEN date_trunc('quarter'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone)
                    WHEN 'stop_of_quarter_prev'::public.relative_period_code THEN (date_trunc('quarter'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone) - '1 day'::interval)
                    WHEN 'start_of_quarter_prev'::public.relative_period_code THEN (date_trunc('quarter'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - '3 mons'::interval)))::timestamp with time zone
                    WHEN 'start_of_semester_curr'::public.relative_period_code THEN
                    CASE
                        WHEN (EXTRACT(month FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)) <= (6)::numeric) THEN date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone)
                        ELSE (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone) + '6 mons'::interval)
                    END
                    WHEN 'stop_of_semester_prev'::public.relative_period_code THEN
                    CASE
                        WHEN (EXTRACT(month FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)) <= (6)::numeric) THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone) - '1 day'::interval)
                        ELSE ((date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone) + '6 mons'::interval) - '1 day'::interval)
                    END
                    WHEN 'start_of_semester_prev'::public.relative_period_code THEN
                    CASE
                        WHEN (EXTRACT(month FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)) <= (6)::numeric) THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone) - '6 mons'::interval)
                        ELSE date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone)
                    END
                    WHEN 'start_of_year_curr'::public.relative_period_code THEN date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone)
                    WHEN 'stop_of_year_prev'::public.relative_period_code THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone) - '1 day'::interval)
                    WHEN 'start_of_year_prev'::public.relative_period_code THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - '1 year'::interval)))::timestamp with time zone
                    WHEN 'start_of_quinquennial_curr'::public.relative_period_code THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - ('1 year'::interval * (((EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)))::integer % 5))::double precision))))::timestamp with time zone
                    WHEN 'stop_of_quinquennial_prev'::public.relative_period_code THEN ((date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - ('1 year'::interval * (((EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)))::integer % 5))::double precision))) - '1 day'::interval))::timestamp with time zone
                    WHEN 'start_of_quinquennial_prev'::public.relative_period_code THEN ((date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - ('1 year'::interval * (((EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)))::integer % 5))::double precision))) - '5 years'::interval))::timestamp with time zone
                    WHEN 'start_of_decade_curr'::public.relative_period_code THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - ('1 year'::interval * (((EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)))::integer % 10))::double precision))))::timestamp with time zone
                    WHEN 'stop_of_decade_prev'::public.relative_period_code THEN ((date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - ('1 year'::interval * (((EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)))::integer % 10))::double precision))) - '1 day'::interval))::timestamp with time zone
                    WHEN 'start_of_decade_prev'::public.relative_period_code THEN ((date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - ('1 year'::interval * (((EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)))::integer % 10))::double precision))) - '10 years'::interval))::timestamp with time zone
                    ELSE NULL::timestamp with time zone
                END)::date AS valid_on,
                CASE relative_period.code
                    WHEN 'today'::public.relative_period_code THEN COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)
                    WHEN 'year_prev'::public.relative_period_code THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - '1 year'::interval)))::date
                    WHEN 'year_curr'::public.relative_period_code THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone))::date
                    WHEN 'year_prev_only'::public.relative_period_code THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) - '1 year'::interval)))::date
                    WHEN 'year_curr_only'::public.relative_period_code THEN (date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone))::date
                    ELSE NULL::date
                END AS valid_from,
            (
                CASE relative_period.code
                    WHEN 'today'::public.relative_period_code THEN ('infinity'::date)::timestamp without time zone
                    WHEN 'year_prev'::public.relative_period_code THEN ('infinity'::date)::timestamp without time zone
                    WHEN 'year_curr'::public.relative_period_code THEN ('infinity'::date)::timestamp without time zone
                    WHEN 'year_prev_only'::public.relative_period_code THEN ((date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))::timestamp with time zone))::date - '1 day'::interval)
                    WHEN 'year_curr_only'::public.relative_period_code THEN ((date_trunc('year'::text, (COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE) + '1 year'::interval)))::date - '1 day'::interval)
                    ELSE NULL::timestamp without time zone
                END)::date AS valid_to
           FROM public.relative_period
        )
 SELECT id,
    code,
    name_when_query,
    name_when_input,
    scope,
    enabled,
    valid_on,
    valid_from,
    valid_to
   FROM base_periods;

INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (1, 'today', 'Today', 'From today and onwards', 'input_and_query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (2, 'year_curr', 'Current Year', 'Current year and onwards', 'input_and_query', true);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (3, 'year_prev', 'Previous Year', 'Previous year and onwards', 'input_and_query', true);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (4, 'year_curr_only', NULL, 'Current year only', 'input', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (5, 'year_prev_only', NULL, 'Previous year only', 'input', true);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (6, 'start_of_week_curr', 'Start of Current Week', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (7, 'stop_of_week_prev', 'End of Previous Week', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (8, 'start_of_week_prev', 'Start of Previous Week', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (9, 'start_of_month_curr', 'Start of Current Month', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (10, 'stop_of_month_prev', 'End of Previous Month', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (11, 'start_of_month_prev', 'Start of Previous Month', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (12, 'start_of_quarter_curr', 'Start of Current Quarter', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (13, 'stop_of_quarter_prev', 'End of Previous Quarter', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (14, 'start_of_quarter_prev', 'Start of Previous Quarter', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (15, 'start_of_semester_curr', 'Start of Current Semester', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (16, 'stop_of_semester_prev', 'End of Previous Semester', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (17, 'start_of_semester_prev', 'Start of Previous Semester', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (18, 'start_of_year_curr', 'Start of Current Year', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (19, 'stop_of_year_prev', 'End of Previous Year', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (20, 'start_of_year_prev', 'Start of Previous Year', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (21, 'start_of_quinquennial_curr', 'Start of Current Five-Year Period', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (22, 'stop_of_quinquennial_prev', 'End of Previous Five-Year Period', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (23, 'start_of_quinquennial_prev', 'Start of Previous Five-Year Period', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (24, 'start_of_decade_curr', 'Start of Current Decade', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (25, 'stop_of_decade_prev', 'End of Previous Decade', NULL, 'query', false);
INSERT INTO public.relative_period (id, code, name_when_query, name_when_input, scope, enabled) OVERRIDING SYSTEM VALUE VALUES (26, 'start_of_decade_prev', 'Start of Previous Decade', NULL, 'query', false);
SELECT pg_catalog.setval('public.relative_period_id_seq', 26, true);

CREATE VIEW public.time_context WITH (security_invoker='on') AS
 WITH combined_data AS (
         SELECT 'relative_period'::public.time_context_type AS type,
            ('r_'::text || ((relative_period_with_time.code)::character varying)::text) AS ident,
                CASE
                    WHEN (relative_period_with_time.code = ANY (ARRAY['year_curr'::public.relative_period_code, 'year_curr_only'::public.relative_period_code])) THEN (format('%s (%s)'::text, relative_period_with_time.name_when_query, EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))))::character varying
                    WHEN (relative_period_with_time.code = 'year_prev'::public.relative_period_code) THEN (format('%s (%s)'::text, relative_period_with_time.name_when_query, (EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)) - (1)::numeric)))::character varying
                    ELSE relative_period_with_time.name_when_query
                END AS name_when_query,
                CASE
                    WHEN (relative_period_with_time.code = 'year_curr'::public.relative_period_code) THEN (format('%s (%s->)'::text, relative_period_with_time.name_when_input, EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))))::character varying
                    WHEN (relative_period_with_time.code = 'year_prev'::public.relative_period_code) THEN (format('%s (%s->)'::text, relative_period_with_time.name_when_input, (EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)) - (1)::numeric)))::character varying
                    WHEN (relative_period_with_time.code = 'year_curr_only'::public.relative_period_code) THEN (format('%s (%s)'::text, relative_period_with_time.name_when_input, EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE))))::character varying
                    WHEN (relative_period_with_time.code = 'year_prev_only'::public.relative_period_code) THEN (format('%s (%s)'::text, relative_period_with_time.name_when_input, (EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)) - (1)::numeric)))::character varying
                    ELSE relative_period_with_time.name_when_input
                END AS name_when_input,
            relative_period_with_time.scope,
            relative_period_with_time.valid_from,
            relative_period_with_time.valid_to,
            relative_period_with_time.valid_on,
            relative_period_with_time.code,
            NULL::public.ltree AS path
           FROM public.relative_period_with_time
          WHERE relative_period_with_time.enabled
        UNION ALL
         SELECT 'tag'::public.time_context_type AS type,
            ('t_'::text || ((tag.path)::character varying)::text) AS ident,
            tag.description AS name_when_query,
            tag.description AS name_when_input,
            'input_and_query'::public.relative_period_scope AS scope,
            tag.context_valid_from AS valid_from,
            tag.context_valid_to AS valid_to,
            tag.context_valid_on AS valid_on,
            NULL::public.relative_period_code AS code,
            tag.path
           FROM public.tag
          WHERE (tag.enabled AND (tag.path IS NOT NULL) AND (tag.context_valid_from IS NOT NULL) AND (tag.context_valid_to IS NOT NULL) AND (tag.context_valid_on IS NOT NULL))
        UNION ALL
         SELECT 'year'::public.time_context_type AS type,
            ('y_'::text || (ty.year)::text) AS ident,
            ((ty.year)::text || ' (Data)'::text) AS name_when_query,
            (ty.year)::text AS name_when_input,
            'input_and_query'::public.relative_period_scope AS scope,
            make_date(ty.year, 1, 1) AS valid_from,
            make_date(ty.year, 12, 31) AS valid_to,
            make_date(ty.year, 12, 31) AS valid_on,
            NULL::public.relative_period_code AS code,
            NULL::public.ltree AS path
           FROM public.timesegments_years ty
          WHERE (ty.year <> ALL (ARRAY[(EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)))::integer, ((EXTRACT(year FROM COALESCE((NULLIF(current_setting('app.current_date'::text, true), ''::text))::date, CURRENT_DATE)) - (1)::numeric))::integer]))
        )
 SELECT type,
    ident,
    name_when_query,
    name_when_input,
    scope,
    valid_from,
    valid_to,
    valid_on,
    code,
    path
   FROM combined_data
  ORDER BY type,
        CASE
            WHEN (type = 'year'::public.time_context_type) THEN EXTRACT(year FROM valid_from)
            ELSE NULL::numeric
        END DESC, code, path;
ALTER TABLE ONLY public.relative_period
    ADD CONSTRAINT relative_period_code_key UNIQUE (code);
ALTER TABLE ONLY public.relative_period
    ADD CONSTRAINT relative_period_pkey PRIMARY KEY (id);
CREATE INDEX ix_relative_period_enabled ON public.relative_period USING btree (enabled);
CREATE TRIGGER trigger_prevent_relative_period_id_update BEFORE UPDATE OF id ON public.relative_period FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update();
ALTER TABLE public.relative_period ENABLE ROW LEVEL SECURITY;
CREATE POLICY relative_period_admin_user_manage ON public.relative_period TO admin_user USING (true) WITH CHECK (true);
CREATE POLICY relative_period_authenticated_read ON public.relative_period FOR SELECT TO authenticated USING (true);
CREATE POLICY relative_period_regular_user_read ON public.relative_period FOR SELECT TO regular_user USING (true);
GRANT SELECT ON TABLE public.relative_period TO authenticated;
GRANT SELECT ON TABLE public.relative_period TO regular_user;
GRANT ALL ON TABLE public.relative_period TO admin_user;
GRANT USAGE ON SEQUENCE public.relative_period_id_seq TO authenticated;
GRANT SELECT ON TABLE public.relative_period_with_time TO authenticated;
GRANT SELECT ON TABLE public.relative_period_with_time TO regular_user;
GRANT SELECT ON TABLE public.relative_period_with_time TO admin_user;
GRANT SELECT ON TABLE public.time_context TO authenticated;
GRANT SELECT ON TABLE public.time_context TO regular_user;
GRANT SELECT ON TABLE public.time_context TO admin_user;

-- 4. The released import_job constraints and functions.
ALTER TABLE public.import_job ADD CONSTRAINT snapshot_has_time_context_conditionally CHECK ((((((definition_snapshot -> 'import_definition'::text) ->> 'valid_time_from'::text) = 'time_context'::text) AND (definition_snapshot ? 'time_context'::text)) OR (((definition_snapshot -> 'import_definition'::text) ->> 'valid_time_from'::text) <> 'time_context'::text)));
ALTER TABLE public.import_job ADD CONSTRAINT job_parameters_must_match_valid_time_from_mode CHECK (
CASE ((definition_snapshot -> 'import_definition'::text) ->> 'valid_time_from'::text)
    WHEN 'job_provided'::text THEN ((default_valid_from IS NOT NULL) AND (default_valid_to IS NOT NULL))
    WHEN 'source_columns'::text THEN ((time_context_ident IS NULL) AND (default_valid_from IS NULL) AND (default_valid_to IS NULL))
    ELSE true
END);

CREATE OR REPLACE FUNCTION admin.import_job_derive()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    definition public.import_definition;
    v_snapshot JSONB;
BEGIN
    SELECT * INTO definition
    FROM public.import_definition
    WHERE id = NEW.definition_id;

    -- Check if definition exists and is marked as valid
    IF NOT FOUND OR NOT definition.valid THEN
        RAISE EXCEPTION 'Cannot create import job: Import definition % (%) is not valid. Error: %',
            NEW.definition_id, COALESCE(definition.name, 'N/A'), COALESCE(definition.validation_error, 'Definition not found or not marked valid');
    END IF;

    -- Validate time_context_ident if provided on the job
    IF NEW.time_context_ident IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.time_context WHERE ident = NEW.time_context_ident) THEN
        RAISE EXCEPTION 'Cannot create import job: Invalid time_context_ident % provided for the job does not exist in public.time_context.', NEW.time_context_ident;
    END IF;

    IF NEW.slug IS NULL THEN
        NEW.slug := format('import_job_%s', NEW.id);
    END IF;

    NEW.upload_table_name := format('%I', NEW.slug || '_upload');
    NEW.data_table_name := format('%I', NEW.slug || '_data');

    -- Populate the definition_snapshot JSONB with explicit keys matching table names
    SELECT jsonb_build_object(
        'import_definition', (SELECT row_to_json(d) FROM public.import_definition d WHERE d.id = NEW.definition_id),
        'import_step_list', (SELECT jsonb_agg(row_to_json(s) ORDER BY s.priority) FROM public.import_step s JOIN public.import_definition_step ds_link ON s.id = ds_link.step_id WHERE ds_link.definition_id = NEW.definition_id),
        'import_data_column_list', (
            SELECT jsonb_agg(row_to_json(dc) ORDER BY s_link.priority, dc.priority, dc.column_name)
            FROM public.import_data_column dc
            JOIN public.import_step s_link ON dc.step_id = s_link.id
            JOIN public.import_definition_step ds_link ON s_link.id = ds_link.step_id
            WHERE ds_link.definition_id = NEW.definition_id
        ),
        'import_source_column_list', (SELECT jsonb_agg(row_to_json(sc_list) ORDER BY sc_list.priority) FROM public.import_source_column sc_list WHERE sc_list.definition_id = NEW.definition_id),
        'import_mapping_list', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'mapping', row_to_json(m_map),
                    'source_column', row_to_json(sc_map),
                    'target_data_column', row_to_json(dc_map)
                ) ORDER BY s_link.priority, dc_map.priority, dc_map.column_name, m_map.id
            )
            FROM public.import_mapping m_map
            LEFT JOIN public.import_source_column sc_map ON m_map.source_column_id = sc_map.id AND sc_map.definition_id = m_map.definition_id -- Ensure source_column is for the same definition
            JOIN public.import_data_column dc_map ON m_map.target_data_column_id = dc_map.id
            JOIN public.import_step s_link ON dc_map.step_id = s_link.id
            JOIN public.import_definition_step ds_map_link ON s_link.id = ds_map_link.step_id AND ds_map_link.definition_id = m_map.definition_id -- Ensure data_column's step is linked to this definition
            WHERE m_map.definition_id = NEW.definition_id
        )
    ) INTO v_snapshot;

    IF v_snapshot IS NULL OR NOT (
        v_snapshot ? 'import_definition' AND
        v_snapshot ? 'import_step_list' AND
        v_snapshot ? 'import_data_column_list' AND
        v_snapshot ? 'import_source_column_list' AND
        v_snapshot ? 'import_mapping_list'
    ) THEN
         RAISE EXCEPTION 'Failed to generate a complete definition snapshot for definition_id %. It is missing one or more required keys: import_definition, import_step_list, import_data_column_list, import_source_column_list, import_mapping_list.', NEW.definition_id;
    END IF;

    -- Validate and set default validity dates based on the definition's declarative valid_time_from
    IF definition.valid_time_from = 'job_provided' THEN
        -- Case A: The definition requires job-level dates. The user must provide EITHER a time_context_ident OR explicit dates, but not both.
        IF NEW.time_context_ident IS NOT NULL AND (NEW.default_valid_from IS NOT NULL OR NEW.default_valid_to IS NOT NULL) THEN
            RAISE EXCEPTION 'Cannot specify both a time_context_ident and explicit default_valid_from/to dates for a job with definition %.', definition.name;
        END IF;
        IF NEW.time_context_ident IS NULL AND (NEW.default_valid_from IS NULL OR NEW.default_valid_to IS NULL) THEN
            RAISE EXCEPTION 'Must specify either a time_context_ident or explicit default_valid_from/to dates for a job with definition %.', definition.name;
        END IF;

        -- If time_context_ident is provided, derive the default dates.
        IF NEW.time_context_ident IS NOT NULL THEN
            SELECT tc.valid_from, tc.valid_to
            INTO NEW.default_valid_from, NEW.default_valid_to
            FROM public.time_context tc
            WHERE tc.ident = NEW.time_context_ident;

            SELECT v_snapshot || jsonb_build_object('time_context', row_to_json(tc))
            INTO v_snapshot
            FROM public.time_context tc WHERE tc.ident = NEW.time_context_ident;
        END IF;

    ELSIF definition.valid_time_from = 'source_columns' THEN
        IF NEW.time_context_ident IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot specify a time_context_ident for an import job when its definition (%) has valid_time_from="source_columns".', definition.name;
        END IF;
        IF NEW.default_valid_from IS NOT NULL OR NEW.default_valid_to IS NOT NULL THEN
            RAISE EXCEPTION 'Cannot specify default_valid_from/to for an import job when its definition (%) has valid_time_from="source_columns".', definition.name;
        END IF;
    END IF;

    -- Resolve unique_units: job override > definition default
    IF NEW.unique_units IS NULL THEN
        NEW.unique_units := COALESCE(
            definition.unique_units,
            (definition.valid_time_from = 'job_provided')
        );
    END IF;

    -- Validate: prevent job_provided + unique_units=FALSE
    IF definition.valid_time_from = 'job_provided' AND NEW.unique_units = FALSE THEN
        RAISE EXCEPTION 'Cannot set unique_units=FALSE for a job_provided import (definition %). All rows share the same time period, so duplicate units are nonsensical.', definition.name;
    END IF;

    IF NEW.default_data_source_code IS NULL AND definition.data_source_id IS NOT NULL THEN
        SELECT ds.code
        INTO NEW.default_data_source_code
        FROM public.data_source ds
        WHERE ds.id = definition.data_source_id;
    END IF;

    -- Set the user_id from the current authenticated user
    IF NEW.user_id IS NULL THEN
        NEW.user_id := auth.uid();
    END IF;

    -- Set expires_at based on created_at and definition's retention period
    NEW.expires_at := NEW.created_at + COALESCE(definition.default_retention_period, '18 months'::INTERVAL);

    -- Pre-calculate max priorities from the snapshot for weighted progress calculation
    SELECT MAX((s->>'priority')::int)
    INTO NEW.max_analysis_priority
    FROM jsonb_array_elements(v_snapshot->'import_step_list') s
    WHERE s->>'analyse_procedure' IS NOT NULL;


    NEW.definition_snapshot := v_snapshot;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.import_job_clone(p_source_job_id integer, p_slug text DEFAULT NULL::text)
 RETURNS import_job
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_source_job public.import_job;
    v_new_job public.import_job;
    v_source_upload_table_exists BOOLEAN;
    v_source_columns text[];
    v_column_list text;
BEGIN
    -- 1. Get the source job record
    SELECT * INTO v_source_job FROM public.import_job WHERE id = p_source_job_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source import job with ID % not found.', p_source_job_id;
    END IF;

    -- 2. Create a new job by inserting a copy of the old one's configuration.
    -- The BEFORE INSERT trigger `import_job_derive_trigger` will handle setting a new slug,
    -- table names, snapshot, user_id (to current user), expires_at, etc.
    INSERT INTO public.import_job (
        slug,
        description,
        note,
        time_context_ident,
        default_valid_from,
        default_valid_to,
        default_data_source_code,
        analysis_batch_size,
        processing_batch_size,
        review,
        edit_comment,
        definition_id
    ) VALUES (
        p_slug,
        'Clone of job #' || v_source_job.id || ': ' || COALESCE(v_source_job.description, ''),
        v_source_job.note,
        v_source_job.time_context_ident,
        CASE WHEN v_source_job.time_context_ident IS NOT NULL THEN NULL ELSE v_source_job.default_valid_from END,
        CASE WHEN v_source_job.time_context_ident IS NOT NULL THEN NULL ELSE v_source_job.default_valid_to END,
        v_source_job.default_data_source_code,
        v_source_job.analysis_batch_size,
        v_source_job.processing_batch_size,
        v_source_job.review,
        v_source_job.edit_comment,
        v_source_job.definition_id
    ) RETURNING * INTO v_new_job;

    -- 3. Check if the source upload table exists.
    SELECT to_regclass('public.' || v_source_job.upload_table_name) IS NOT NULL INTO v_source_upload_table_exists;

    -- 4. If it exists, copy data from old upload table to new upload table.
    -- The definition may have changed since the source job was created (for
    -- example a statistical variable disabled), so the source can have columns
    -- the new job does not map. They are kept as ignored columns
    -- (admin.import_job_keep_ignored_columns, STATBUS-545), then the rows are
    -- copied column by name.
    IF v_source_upload_table_exists THEN
        RAISE DEBUG '[Job Clone] Copying data from % to %', v_source_job.upload_table_name, v_new_job.upload_table_name;
        SELECT array_agg(c.column_name::text ORDER BY c.ordinal_position) INTO v_source_columns
        FROM information_schema.columns AS c
        WHERE c.table_schema = 'public' AND c.table_name = v_source_job.upload_table_name;
        PERFORM admin.import_job_keep_ignored_columns(v_new_job.id, v_source_columns);
        SELECT string_agg(format('%I', col), ', ') INTO v_column_list FROM unnest(v_source_columns) AS col;
        EXECUTE format('INSERT INTO public.%I (%s) SELECT %s FROM public.%I',
                       v_new_job.upload_table_name, v_column_list, v_column_list, v_source_job.upload_table_name);
        
        -- The AFTER INSERT trigger on the new upload table will automatically set the
        -- new job's state to 'upload_completed', which in turn will enqueue it for processing.
        RAISE DEBUG '[Job Clone] Data copy complete. Job % has been enqueued automatically.', v_new_job.id;
    ELSE
        RAISE DEBUG '[Job Clone] Source upload table % not found. New job % created in "waiting_for_upload" state.', v_source_job.upload_table_name, v_new_job.id;
    END IF;
    
    -- 5. Return the newly created job.
    RETURN v_new_job;
END;
$function$
;

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
    PERFORM admin.add_rls_regular_user_can_read('public.relative_period'::regclass);
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

END;
