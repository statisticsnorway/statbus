-- STATBUS-606: time frames.
--
-- A time frame is the window a user looks at the timelines through. There are
-- three kinds (public.time_frame_kind):
--   * live      "Live frame (YYYY)": 1 January of the current year to
--               infinity, read as of today. Changes go straight in.
--   * relative  "Previous frame (YYYY)": the previous year, 1 January to
--               31 December, read as of 31 December. It moves on 1 January.
--   * fixed     "Frame YYYY": one closed year, forever: the previous year and
--               every year with data.
--
-- The state this test asserts:
--   * public.time_frame lists exactly those frames for a given current date,
--     with their period, the date they are read as of, and, for a fixed frame,
--     the relative frame it currently equals (the menu leaves those out).
--   * On 1 January the live and relative frames move; fixed frames do not.
--   * An import job on a frame derives its dates from it; a clone of a job on
--     a live or relative frame derives them again, so a recurring job follows
--     the calendar, and a clone of a job on a fixed frame keeps its year.
SET datestyle TO 'ISO, DMY';

BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

\o /dev/null
\set ECHO none
\i samples/norway/getting-started.sql
\o
\set ECHO all

-- Years with data: 2022 and 2024 (2023 has none, so it is not a frame).
DELETE FROM public.timesegments_years WHERE true; -- test setup: start from known years
INSERT INTO public.timesegments_years (year) VALUES (2022), (2024), (2026);

\echo "On 2026-11-10: the live frame, the relative frame and the fixed frames"
SELECT set_config('app.current_date', '2026-11-10', true) IS NOT NULL AS date_set;
SELECT ident, kind, name, valid_from, valid_to, valid_on, equals_frame_ident
FROM public.time_frame
ORDER BY kind, valid_from DESC;

\echo "The menu leaves out a fixed frame that equals a relative frame"
SELECT ident, name
FROM public.time_frame
WHERE equals_frame_ident IS NULL
ORDER BY kind, valid_from DESC;

\echo "Import jobs derive their dates from their frame"
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, time_frame_ident)
SELECT d.id, 'tf_606_' || f.ident, 'STATBUS-606 job on ' || f.ident, 'test 399', f.ident
FROM public.import_definition AS d
CROSS JOIN (VALUES ('live'), ('prev'), ('y_2024')) AS f(ident)
WHERE d.slug = 'legal_unit_job_provided';
SELECT slug, time_frame_ident, default_valid_from, default_valid_to,
       definition_snapshot->'time_frame'->>'ident' AS snapshot_frame
FROM public.import_job
WHERE slug LIKE 'tf_606_%'
ORDER BY slug;

\echo "On 2027-01-01 the live and relative frames have moved; fixed frames have not"
SELECT set_config('app.current_date', '2027-01-01', true) IS NOT NULL AS date_set;
SELECT ident, kind, name, valid_from, valid_to, valid_on, equals_frame_ident
FROM public.time_frame
ORDER BY kind, valid_from DESC;

\echo "A clone re-derives a live or relative frame's dates; a fixed frame keeps its year"
SELECT j.slug AS source,
       (c).time_frame_ident, (c).default_valid_from, (c).default_valid_to
FROM (
    SELECT j.slug, public.import_job_clone(j.id, j.slug || '_clone') AS c
    FROM public.import_job AS j
    WHERE j.slug LIKE 'tf_606_%'
    ORDER BY j.slug
) AS j
ORDER BY j.slug;

\echo "A job names a frame that exists"
SAVEPOINT unknown_frame;
INSERT INTO public.import_job (definition_id, slug, description, edit_comment, time_frame_ident)
SELECT d.id, 'tf_606_unknown', 'unknown frame', 'test 399', 'r_year_curr'
FROM public.import_definition AS d WHERE d.slug = 'legal_unit_job_provided';
ROLLBACK TO SAVEPOINT unknown_frame;

ROLLBACK;
