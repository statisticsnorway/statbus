\set ON_ERROR_STOP on
-- Assertions raise on mismatch, so psql and the wrapper return failure.
CREATE TEMP TABLE mixed_expected (kind text, name text, valid_from date, valid_until date);
INSERT INTO mixed_expected
SELECT kind, 'Mixed ' || kind || ' ' || n || ' ' || y, make_date(y, 1, 1),
       CASE WHEN y = 2022 THEN 'infinity'::date ELSE make_date(y + 1, 1, 1) END
FROM (VALUES ('LU', 400, 200), ('ES', 800, 400), ('informal', 400, 200)) AS sizes(kind, total, existing)
CROSS JOIN generate_series(2020, 2022) AS y
CROSS JOIN LATERAL generate_series(1, CASE WHEN y = 2020 THEN existing ELSE total END) AS n;
CREATE TEMP VIEW mixed_actual AS
SELECT 'LU'::text AS kind, name, valid_from, valid_until FROM public.legal_unit WHERE name LIKE 'Mixed LU %'
UNION ALL
SELECT CASE WHEN name LIKE 'Mixed ES %' THEN 'ES' ELSE 'informal' END, name, valid_from, valid_until
FROM public.establishment WHERE name LIKE 'Mixed ES %' OR name LIKE 'Mixed informal %';
DO LANGUAGE plpgsql $mixed_check$
DECLARE
    v_job record;
    v_counts record;
    v_actual jsonb;
BEGIN
    IF EXISTS ((TABLE mixed_expected EXCEPT ALL TABLE mixed_actual)
               UNION ALL (TABLE mixed_actual EXCEPT ALL TABLE mixed_expected)) THEN
        RAISE EXCEPTION 'Mixed logical identities or exact history intervals differ';
    END IF;
    FOR v_job IN SELECT * FROM (VALUES
        ('import_mixed_lu', 800, 200, 600),
        ('import_mixed_es', 1600, 400, 1200),
        ('import_mixed_informal', 800, 200, 600)
    ) AS jobs(slug, rows, inserts, updates) LOOP
        IF (SELECT count(*) FROM public.import_job
            WHERE slug = v_job.slug AND state = 'finished' AND total_rows = v_job.rows
              AND imported_rows = v_job.rows AND error_count = 0) <> 1 THEN
            RAISE EXCEPTION 'Mixed job % did not finish exact rows', v_job.slug;
        END IF;
        EXECUTE format($SQL$
            SELECT count(*) AS total, count(*) FILTER (WHERE operation = 'insert') AS inserts,
                   count(*) FILTER (WHERE operation = 'update') AS updates,
                   count(*) FILTER (WHERE state = 'processed') AS processed,
                   count(DISTINCT batch_seq) AS batches
            FROM public.%1$I
        $SQL$, v_job.slug || '_data') INTO v_counts;
        IF (v_counts.total, v_counts.inserts, v_counts.updates, v_counts.processed)
           IS DISTINCT FROM (v_job.rows::bigint, v_job.inserts::bigint, v_job.updates::bigint, v_job.rows::bigint)
           OR v_counts.batches < 2 THEN
            RAISE EXCEPTION 'Mixed analysis/processing %: %', v_job.slug, row_to_json(v_counts);
        END IF;
    END LOOP;
    -- Each logical identity retains one internal identity over its exact history.
    IF (SELECT count(*) FROM (
        SELECT split_part(name, ' ', 3) FROM public.legal_unit WHERE name LIKE 'Mixed LU %'
        GROUP BY split_part(name, ' ', 3) HAVING count(DISTINCT id) = 1
    ) AS identities) <> 400 OR
       (SELECT count(*) FROM (
        SELECT split_part(name, ' ', 2), split_part(name, ' ', 3)
        FROM public.establishment WHERE name LIKE 'Mixed ES %' OR name LIKE 'Mixed informal %'
        GROUP BY split_part(name, ' ', 2), split_part(name, ' ', 3) HAVING count(DISTINCT id) = 1
    ) AS identities) <> 1200 THEN
        RAISE EXCEPTION 'Mixed logical identities did not retain stable internal identity';
    END IF;
    -- Shared enterprise dependencies must be retained as whole processing batches.
    IF (SELECT count(DISTINCT enterprise_id) FROM public.import_mixed_lu_data
        WHERE name IN ('Mixed LU 1 2021', 'Mixed LU 2 2021')) <> 1 OR
       (SELECT count(DISTINCT batch_seq) FROM public.import_mixed_lu_data
        WHERE name IN ('Mixed LU 1 2021', 'Mixed LU 2 2021', 'Mixed LU 1 2022', 'Mixed LU 2 2022')) <> 1 OR
       (SELECT count(DISTINCT enterprise_id) FROM public.import_mixed_informal_data
        WHERE name IN ('Mixed informal 1 2021', 'Mixed informal 2 2021')) <> 1 OR
       (SELECT count(DISTINCT batch_seq) FROM public.import_mixed_informal_data
        WHERE name IN ('Mixed informal 1 2021', 'Mixed informal 2 2021', 'Mixed informal 1 2022', 'Mixed informal 2 2022')) <> 1 OR
       (SELECT count(*) FROM (
        SELECT legal_unit_id FROM public.import_mixed_es_data GROUP BY legal_unit_id
        HAVING count(*) = 4 AND count(DISTINCT batch_seq) = 1
       ) AS parents) <> 400 THEN
        RAISE EXCEPTION 'Mixed dependency groups were not retained in whole batches';
    END IF;
    -- Formal children keep their logical legal parent and complete temporal coverage.
    IF (SELECT count(*) FROM public.establishment AS es
        JOIN public.legal_unit AS lu ON lu.id = es.legal_unit_id
          AND lu.valid_from <= es.valid_from AND es.valid_from < lu.valid_until
        JOIN (SELECT id, range_agg(valid_range) AS coverage FROM public.legal_unit GROUP BY id) AS ph
          ON ph.id = es.legal_unit_id AND ph.coverage @> es.valid_range
        WHERE es.name LIKE 'Mixed ES %' AND
          split_part(lu.name, ' ', 3)::integer = CASE
            WHEN split_part(es.name, ' ', 3)::integer <= 400
              THEN ((split_part(es.name, ' ', 3)::integer - 1) % 200) + 1
            ELSE ((split_part(es.name, ' ', 3)::integer - 401) % 200) + 201 END) <> 2000 THEN
        RAISE EXCEPTION 'Mixed formal logical parent or temporal coverage mismatch';
    END IF;
    FOR v_job IN SELECT * FROM (VALUES (2020, 200, 200, 199), (2021, 400, 400, 399),
                                       (2022, 400, 400, 399)) AS years(y, units, parents, enterprises) LOOP
        IF (SELECT count(*) FROM (
            SELECT enterprise_id FROM public.legal_unit WHERE name LIKE 'Mixed LU %'
              AND valid_from <= make_date(v_job.y, 1, 1) AND make_date(v_job.y, 1, 1) < valid_until
            GROUP BY enterprise_id HAVING count(*) FILTER (WHERE primary_for_enterprise) = 1
        ) AS groups) <> v_job.enterprises OR
           (SELECT count(*) FROM (
            SELECT enterprise_id FROM public.establishment WHERE name LIKE 'Mixed informal %'
              AND valid_from <= make_date(v_job.y, 1, 1) AND make_date(v_job.y, 1, 1) < valid_until
            GROUP BY enterprise_id HAVING count(*) FILTER (WHERE primary_for_enterprise) = 1
        ) AS groups) <> v_job.enterprises OR
           (SELECT count(*) FROM (
            SELECT legal_unit_id FROM public.establishment WHERE name LIKE 'Mixed ES %'
              AND valid_from <= make_date(v_job.y, 1, 1) AND make_date(v_job.y, 1, 1) < valid_until
            GROUP BY legal_unit_id HAVING count(*) FILTER (WHERE primary_for_legal_unit) = 1
        ) AS groups) <> v_job.parents THEN
            RAISE EXCEPTION 'Mixed parents must each retain exactly one primary at %', v_job.y;
        END IF;
        SELECT jsonb_build_array(count(DISTINCT id), count(DISTINCT enterprise_id),
                                count(*) FILTER (WHERE primary_for_enterprise)) INTO v_actual
        FROM public.legal_unit WHERE name LIKE 'Mixed LU %'
          AND valid_from <= make_date(v_job.y, 1, 1) AND make_date(v_job.y, 1, 1) < valid_until;
        IF v_actual <> jsonb_build_array(v_job.units, v_job.enterprises, v_job.enterprises) THEN
            RAISE EXCEPTION 'Mixed LU primary/enterprise counts at %: %', v_job.y, v_actual;
        END IF;
        SELECT jsonb_build_array(count(DISTINCT id), count(DISTINCT enterprise_id),
                                count(*) FILTER (WHERE primary_for_enterprise),
                                count(*) FILTER (WHERE legal_unit_id IS NULL)) INTO v_actual
        FROM public.establishment WHERE name LIKE 'Mixed informal %'
          AND valid_from <= make_date(v_job.y, 1, 1) AND make_date(v_job.y, 1, 1) < valid_until;
        IF v_actual <> jsonb_build_array(v_job.units, v_job.enterprises, v_job.enterprises, v_job.units) THEN
            RAISE EXCEPTION 'Mixed informal primary/enterprise counts at %: %', v_job.y, v_actual;
        END IF;
        SELECT jsonb_build_array(count(DISTINCT id), count(DISTINCT legal_unit_id),
                                count(*) FILTER (WHERE primary_for_legal_unit)) INTO v_actual
        FROM public.establishment WHERE name LIKE 'Mixed ES %'
          AND valid_from <= make_date(v_job.y, 1, 1) AND make_date(v_job.y, 1, 1) < valid_until;
        IF v_actual <> jsonb_build_array(v_job.units * 2, v_job.parents, v_job.parents) THEN
            RAISE EXCEPTION 'Mixed formal primary counts at %: %', v_job.y, v_actual;
        END IF;
    END LOOP;
END;
$mixed_check$;
SELECT 'Mixed exact histories, operations, parent coverage and primary counts passed' AS dataset_check;
