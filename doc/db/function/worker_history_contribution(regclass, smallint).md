```sql
CREATE OR REPLACE PROCEDURE worker.history_contribution(IN p_source regclass, IN p_sign smallint)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF to_regclass('pg_temp.hd_v') IS NOT NULL THEN DROP TABLE pg_temp.hd_v; END IF;
    EXECUTE format($SQL$
    CREATE TEMP TABLE hd_v AS
    SELECT s.unit_type, s.unit_id, s.valid_from, s.valid_to, s.valid_until, s.birth_date, s.death_date,
           s.used_for_counting, s.name, s.stats_summary,
           s.primary_activity_category_path, s.secondary_activity_category_path, s.sector_path, s.legal_form_id,
           s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id,
           (s.physical_address_part1, s.physical_address_part2, s.physical_address_part3,
            s.physical_postcode, s.physical_postplace)::text AS addr,
           public.unit_existence_from(s.valid_from, s.birth_date) AS ef,
           public.unit_existence_until(s.valid_until, s.death_date) AS eu
      FROM %1$s AS s
      JOIN pg_temp.hd_units AS u ON u.unit_type = s.unit_type AND u.unit_id = s.unit_id
    $SQL$, p_source);
    CREATE INDEX ON hd_v (unit_type, unit_id, valid_from);
    ANALYZE hd_v;

    -- Stock: +1/-1 at each version's existence window (today: latest version overlapping the period,
    -- existing at its end; versions of one unit do not overlap, so the sums agree), countable likewise.
    -- Dates are bucketed to their month (on_month, see its column comment): exact at every month end, and
    -- a unit's changes within one month collapse into one row, or cancel. A version without a known start
    -- (-infinity) enters at on_month -infinity, before every period; an open end (infinity) never leaves.
    INSERT INTO pg_temp.hd_stock
    SELECT v.unit_id, p_sign, v.unit_type, v.primary_activity_category_path, v.secondary_activity_category_path,
           v.sector_path, v.legal_form_id, v.physical_region_path, v.physical_country_id, v.unit_size_id, v.status_id,
           date_trunc('month', x.d)::date, sum(x.ne)::int, sum(x.nc)::int, NULL::jsonb
      FROM hd_v AS v
     CROSS JOIN LATERAL (VALUES (v.ef, 1, v.used_for_counting::int), (v.eu, -1, -v.used_for_counting::int)) AS x(d, ne, nc)
     WHERE v.ef < v.eu AND x.d <> 'infinity'::date
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
    HAVING sum(x.ne) <> 0 OR sum(x.nc) <> 0;
    -- Stats valid: a counted version's summary holds from valid_from until valid_until. Within one month a
    -- unit's leaving and re-entering summaries are added; a row where every key's in and out flows are
    -- equal changes no stock and is not kept.
    INSERT INTO pg_temp.hd_stock
    SELECT v.unit_id, p_sign, v.unit_type, v.primary_activity_category_path, v.secondary_activity_category_path,
           v.sector_path, v.legal_form_id, v.physical_region_path, v.physical_country_id, v.unit_size_id, v.status_id,
           date_trunc('month', x.d)::date, 0, 0, public.jsonb_stats_delta_agg(x.sd)
      FROM hd_v AS v
     CROSS JOIN LATERAL (VALUES (v.valid_from, public.jsonb_stats_to_delta(v.stats_summary)),
                                (v.valid_until, public.jsonb_stats_negate(public.jsonb_stats_to_delta(v.stats_summary)))) AS x(d, sd)
     WHERE v.used_for_counting AND x.d <> 'infinity'::date
     GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
    HAVING EXISTS (SELECT 1 FROM jsonb_each(public.jsonb_stats_delta_agg(x.sd) - 'type'::text) AS e
                    WHERE e.value->'in' IS DISTINCT FROM e.value->'out');

    -- Calendar periods holding any of the unit's edges, independent of the data's date range.
    IF to_regclass('pg_temp.hd_ep') IS NOT NULL THEN DROP TABLE pg_temp.hd_ep; END IF;
    CREATE TEMP TABLE hd_ep AS
    SELECT DISTINCT v.unit_type, v.unit_id, p.resolution, p.year, p.month, p.curr_start, p.curr_stop, p.prev_stop
      FROM hd_v AS v
     CROSS JOIN LATERAL (VALUES (v.valid_from), (v.valid_until), (v.birth_date), (v.death_date), (v.ef), (v.eu)) AS e(d)
     CROSS JOIN LATERAL (VALUES
            ('year'::public.history_resolution, extract(year FROM e.d)::int, NULL::int,
             make_date(extract(year FROM e.d)::int, 1, 1), make_date(extract(year FROM e.d)::int, 12, 31),
             make_date(extract(year FROM e.d)::int - 1, 12, 31)),
            ('year-month'::public.history_resolution, extract(year FROM e.d)::int, extract(month FROM e.d)::int,
             date_trunc('month', e.d)::date, (date_trunc('month', e.d) + interval '1 month' - interval '1 day')::date,
             (date_trunc('month', e.d) - interval '1 day')::date)) AS p(resolution, year, month, curr_start, curr_stop, prev_stop)
     WHERE e.d IS NOT NULL AND isfinite(e.d);
    CREATE INDEX ON hd_ep (unit_type, unit_id);
    ANALYZE hd_ep;

    -- Flows: the unit at prev_stop (p) and curr_stop (c), as the former statistical_history_facet_def compared
    -- them. A period in which the unit changed nothing (all 18 counts zero) stores no row.
    INSERT INTO pg_temp.hd_flow
    SELECT * FROM (
    SELECT ep.unit_id, p_sign, ep.resolution, ep.year, ep.month, ep.unit_type,
           COALESCE(c.primary_activity_category_path, p.primary_activity_category_path),
           COALESCE(c.secondary_activity_category_path, p.secondary_activity_category_path),
           COALESCE(c.sector_path, p.sector_path), COALESCE(c.legal_form_id, p.legal_form_id),
           COALESCE(c.physical_region_path, p.physical_region_path), COALESCE(c.physical_country_id, p.physical_country_id),
           COALESCE(c.unit_size_id, p.unit_size_id), COALESCE(c.status_id, p.status_id),
           ARRAY[(c.unit_id IS NOT NULL)::int - (p.unit_id IS NOT NULL)::int,
                 (c.unit_id IS NOT NULL AND p.unit_id IS NULL)::int,
                 (p.unit_id IS NOT NULL AND c.unit_id IS NULL)::int,
                 COALESCE(c.used_for_counting, false)::int - COALESCE(p.used_for_counting, false)::int,
                 (COALESCE(c.used_for_counting, false) AND NOT COALESCE(p.used_for_counting, false))::int,
                 (COALESCE(p.used_for_counting, false) AND NOT COALESCE(c.used_for_counting, false))::int,
                 (COALESCE(l.used_for_counting, false) AND COALESCE(l.birth_date BETWEEN ep.curr_start AND ep.curr_stop, false))::int,
                 (COALESCE(l.used_for_counting, false) AND COALESCE(l.death_date BETWEEN ep.curr_start AND ep.curr_stop, false))::int,
                 (b.both AND c.name IS DISTINCT FROM p.name)::int,
                 (b.both AND c.primary_activity_category_path IS DISTINCT FROM p.primary_activity_category_path)::int,
                 (b.both AND c.secondary_activity_category_path IS DISTINCT FROM p.secondary_activity_category_path)::int,
                 (b.both AND c.sector_path IS DISTINCT FROM p.sector_path)::int,
                 (b.both AND c.legal_form_id IS DISTINCT FROM p.legal_form_id)::int,
                 (b.both AND c.physical_region_path IS DISTINCT FROM p.physical_region_path)::int,
                 (b.both AND c.physical_country_id IS DISTINCT FROM p.physical_country_id)::int,
                 (b.both AND c.addr IS DISTINCT FROM p.addr)::int,
                 (b.both AND c.unit_size_id IS DISTINCT FROM p.unit_size_id)::int,
                 (b.both AND c.status_id IS DISTINCT FROM p.status_id)::int],
           NULL::jsonb
      FROM hd_ep AS ep
      LEFT JOIN hd_v AS c ON c.unit_type = ep.unit_type AND c.unit_id = ep.unit_id
           AND c.valid_from <= ep.curr_stop AND ep.curr_stop < c.valid_until
           AND c.ef <= ep.curr_stop AND ep.curr_stop < c.eu
      LEFT JOIN hd_v AS p ON p.unit_type = ep.unit_type AND p.unit_id = ep.unit_id
           AND p.valid_from <= ep.prev_stop AND ep.prev_stop < p.valid_until
           AND p.ef <= ep.prev_stop AND ep.prev_stop < p.eu
      LEFT JOIN LATERAL (SELECT l.used_for_counting, l.birth_date, l.death_date FROM hd_v AS l
                          WHERE l.unit_type = ep.unit_type AND l.unit_id = ep.unit_id
                            AND l.valid_from <= ep.curr_stop AND l.valid_to >= ep.curr_start
                          ORDER BY l.valid_from DESC, l.valid_until DESC LIMIT 1) AS l ON true
     CROSS JOIN LATERAL (SELECT COALESCE(p.used_for_counting AND c.used_for_counting, false) AS both) AS b
     WHERE c.unit_id IS NOT NULL OR p.unit_id IS NOT NULL) AS r(unit_id, sign, resolution, year, month, unit_type,
         primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id,
         physical_region_path, physical_country_id, unit_size_id, status_id, flows, stats_ended)
     WHERE r.flows <> array_fill(0, ARRAY[18]);

    -- Stats ended: the latest counted version overlapping a period counts for the period's stats; when it
    -- ended inside the period it is not in the stock at the period end, so it is added here.
    INSERT INTO pg_temp.hd_flow
    SELECT v.unit_id, p_sign, ep.resolution, ep.year, ep.month, v.unit_type, v.primary_activity_category_path,
           v.secondary_activity_category_path, v.sector_path, v.legal_form_id, v.physical_region_path,
           v.physical_country_id, v.unit_size_id, v.status_id,
           array_fill(0, ARRAY[18]), public.jsonb_stats_to_delta(v.stats_summary)
      FROM hd_ep AS ep
      JOIN hd_v AS v ON v.unit_type = ep.unit_type AND v.unit_id = ep.unit_id
       AND v.used_for_counting AND v.valid_from <= ep.curr_stop
       AND ep.curr_start < v.valid_until AND v.valid_until <= ep.curr_stop
     WHERE NOT EXISTS (SELECT 1 FROM hd_v AS w WHERE w.unit_type = v.unit_type AND w.unit_id = v.unit_id
                          AND w.valid_from > v.valid_from AND w.valid_from <= ep.curr_stop);
END;
$procedure$
```
