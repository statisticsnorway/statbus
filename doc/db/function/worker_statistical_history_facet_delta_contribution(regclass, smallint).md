```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_contribution(IN p_source regclass, IN p_sign smallint)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    IF to_regclass('pg_temp.hd_v') IS NOT NULL THEN DROP TABLE pg_temp.hd_v; END IF;
    EXECUTE format($SQL$
    CREATE TEMP TABLE hd_v AS
    SELECT s.unit_type, s.unit_id, s.valid_from, s.valid_until, s.birth_date, s.death_date,
           s.used_for_counting AS counted, s.name, s.stats_summary,
           s.primary_activity_category_path, s.secondary_activity_category_path, s.sector_path, s.legal_form_id,
           s.physical_region_path, s.physical_country_id, s.unit_size_id, s.status_id,
           (s.physical_address_part1, s.physical_address_part2, s.physical_address_part3,
            s.physical_postcode, s.physical_postplace)::text AS addr,
           public.unit_existence_from(s.valid_from, s.birth_date) AS ef,
           public.unit_existence_until(s.valid_until, s.death_date) AS eu,
           lead(s.valid_from) OVER (PARTITION BY s.unit_type, s.unit_id ORDER BY s.valid_from) AS next_valid_from
      FROM %1$s AS s
      JOIN pg_temp.hd_units AS u ON u.unit_type = s.unit_type AND u.unit_id = s.unit_id
    $SQL$, p_source);  -- a regclass renders as its quoted, schema-qualified name

    -- The existence windows in order, with their neighbours. A version whose window is empty (born after it
    -- ended, or died before it began) is no existence and takes no part.
    IF to_regclass('pg_temp.hd_w') IS NOT NULL THEN DROP TABLE pg_temp.hd_w; END IF;
    CREATE TEMP TABLE hd_w AS
    SELECT v.*,
           lag(v.eu) OVER w IS NOT DISTINCT FROM v.ef AS continues,
           lead(v.ef) OVER w IS NOT DISTINCT FROM v.eu AS continued,
           lag(v.cell) OVER w AS prev_cell, lead(v.cell) OVER w AS next_cell,
           lag(v.counted) OVER w AS prev_counted, lead(v.counted) OVER w AS next_counted,
           lag(v.name) OVER w AS prev_name,
           lag(v.primary_activity_category_path) OVER w AS prev_primary_activity_category_path,
           lag(v.secondary_activity_category_path) OVER w AS prev_secondary_activity_category_path,
           lag(v.sector_path) OVER w AS prev_sector_path, lag(v.legal_form_id) OVER w AS prev_legal_form_id,
           lag(v.physical_region_path) OVER w AS prev_physical_region_path,
           lag(v.physical_country_id) OVER w AS prev_physical_country_id, lag(v.addr) OVER w AS prev_addr,
           lag(v.unit_size_id) OVER w AS prev_unit_size_id, lag(v.status_id) OVER w AS prev_status_id
      FROM (SELECT hd_v.*,
                   ROW(hd_v.primary_activity_category_path, hd_v.secondary_activity_category_path, hd_v.sector_path,
                       hd_v.legal_form_id, hd_v.physical_region_path, hd_v.physical_country_id, hd_v.unit_size_id,
                       hd_v.status_id)::text AS cell
              FROM pg_temp.hd_v WHERE hd_v.ef < hd_v.eu) AS v
    WINDOW w AS (PARTITION BY v.unit_type, v.unit_id ORDER BY v.ef);

    -- One row per event: (kind, count) or (kind, stats delta), in the cell and month it belongs to.
    IF to_regclass('pg_temp.hd_ev') IS NOT NULL THEN DROP TABLE pg_temp.hd_ev; END IF;
    CREATE TEMP TABLE hd_ev AS
    -- Start of a window, in its cell.
    SELECT w.unit_type, w.unit_id, w.primary_activity_category_path, w.secondary_activity_category_path, w.sector_path,
           w.legal_form_id, w.physical_region_path, w.physical_country_id, w.unit_size_id, w.status_id,
           date_trunc('month', w.ef)::date AS on_month, e.kind, 1 AS n, NULL::jsonb AS sd
      FROM pg_temp.hd_w AS w
     CROSS JOIN LATERAL (VALUES
            ('exists_added_count', NOT w.continues),
            ('countable_added_count', w.counted AND NOT (w.continues AND w.prev_counted)),
            ('births', w.counted AND NOT w.continues AND w.ef = w.birth_date),
            ('exists_moved_in_count', w.continues AND w.prev_cell IS DISTINCT FROM w.cell),
            ('countable_moved_in_count', w.continues AND w.prev_cell IS DISTINCT FROM w.cell AND w.prev_counted AND w.counted),
            ('name_change_count', w.continues AND w.prev_counted AND w.counted AND w.name IS DISTINCT FROM w.prev_name),
            ('primary_activity_category_change_count', w.continues AND w.prev_counted AND w.counted
                 AND w.primary_activity_category_path IS DISTINCT FROM w.prev_primary_activity_category_path),
            ('secondary_activity_category_change_count', w.continues AND w.prev_counted AND w.counted
                 AND w.secondary_activity_category_path IS DISTINCT FROM w.prev_secondary_activity_category_path),
            ('sector_change_count', w.continues AND w.prev_counted AND w.counted AND w.sector_path IS DISTINCT FROM w.prev_sector_path),
            ('legal_form_change_count', w.continues AND w.prev_counted AND w.counted AND w.legal_form_id IS DISTINCT FROM w.prev_legal_form_id),
            ('physical_region_change_count', w.continues AND w.prev_counted AND w.counted
                 AND w.physical_region_path IS DISTINCT FROM w.prev_physical_region_path),
            ('physical_country_change_count', w.continues AND w.prev_counted AND w.counted
                 AND w.physical_country_id IS DISTINCT FROM w.prev_physical_country_id),
            ('physical_address_change_count', w.continues AND w.prev_counted AND w.counted AND w.addr IS DISTINCT FROM w.prev_addr),
            ('unit_size_change_count', w.continues AND w.prev_counted AND w.counted AND w.unit_size_id IS DISTINCT FROM w.prev_unit_size_id),
            ('status_change_count', w.continues AND w.prev_counted AND w.counted AND w.status_id IS DISTINCT FROM w.prev_status_id)
           ) AS e(kind, applies)
     WHERE e.applies
    UNION ALL
    -- End of a window, in its cell.
    SELECT w.unit_type, w.unit_id, w.primary_activity_category_path, w.secondary_activity_category_path, w.sector_path,
           w.legal_form_id, w.physical_region_path, w.physical_country_id, w.unit_size_id, w.status_id,
           date_trunc('month', w.eu)::date, e.kind, 1, NULL::jsonb
      FROM pg_temp.hd_w AS w
     CROSS JOIN LATERAL (VALUES
            ('exists_removed_count', NOT w.continued),
            ('countable_removed_count', w.counted AND NOT (w.continued AND w.next_counted)),
            ('deaths', w.counted AND NOT w.continued AND w.eu = w.death_date),
            ('exists_moved_out_count', w.continued AND w.next_cell IS DISTINCT FROM w.cell),
            ('countable_moved_out_count', w.continued AND w.next_cell IS DISTINCT FROM w.cell AND w.counted AND w.next_counted)
           ) AS e(kind, applies)
     WHERE e.applies AND w.eu <> 'infinity'::date
    UNION ALL
    -- Stats of a counted version, from valid_from until valid_until.
    SELECT v.unit_type, v.unit_id, v.primary_activity_category_path, v.secondary_activity_category_path, v.sector_path,
           v.legal_form_id, v.physical_region_path, v.physical_country_id, v.unit_size_id, v.status_id,
           date_trunc('month', x.d)::date, 'stats_delta', 0, x.sd
      FROM pg_temp.hd_v AS v
     CROSS JOIN LATERAL (VALUES (v.valid_from, public.jsonb_stats_to_delta(v.stats_summary)),
                                (v.valid_until, public.jsonb_stats_negate(public.jsonb_stats_to_delta(v.stats_summary)))) AS x(d, sd)
     WHERE v.counted AND v.stats_summary IS NOT NULL AND x.d <> 'infinity'::date
    UNION ALL
    -- Stats of a counted version that ends inside a month (valid_until is not the 1st), when no later
    -- version starts by that month's end; likewise for the year.
    SELECT v.unit_type, v.unit_id, v.primary_activity_category_path, v.secondary_activity_category_path, v.sector_path,
           v.legal_form_id, v.physical_region_path, v.physical_country_id, v.unit_size_id, v.status_id,
           date_trunc('month', v.valid_until)::date, e.kind, 0, public.jsonb_stats_to_delta(v.stats_summary)
      FROM pg_temp.hd_v AS v
     CROSS JOIN LATERAL (VALUES
            ('stats_ended_month', extract(day FROM v.valid_until) <> 1
                AND (v.next_valid_from IS NULL
                     OR v.next_valid_from > (date_trunc('month', v.valid_until) + interval '1 month - 1 day')::date)),
            ('stats_ended_year', NOT (extract(month FROM v.valid_until) = 1 AND extract(day FROM v.valid_until) = 1)
                AND (v.next_valid_from IS NULL
                     OR v.next_valid_from > make_date(extract(year FROM v.valid_until)::int, 12, 31)))
           ) AS e(kind, applies)
     WHERE e.applies AND v.counted AND v.stats_summary IS NOT NULL AND isfinite(v.valid_until);

    INSERT INTO pg_temp.hd_rows (unit_id, sign, unit_type, primary_activity_category_path, secondary_activity_category_path,
           sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           exists_added_count, exists_removed_count, countable_added_count, countable_removed_count,
           exists_moved_in_count, exists_moved_out_count, countable_moved_in_count, countable_moved_out_count,
           births, deaths, name_change_count, primary_activity_category_change_count,
           secondary_activity_category_change_count, sector_change_count, legal_form_change_count,
           physical_region_change_count, physical_country_change_count, physical_address_change_count,
           unit_size_change_count, status_change_count, stats_delta, stats_ended_month, stats_ended_year)
    SELECT r.unit_id, r.sign, r.unit_type, r.primary_activity_category_path, r.secondary_activity_category_path,
           r.sector_path, r.legal_form_id, r.physical_region_path, r.physical_country_id, r.unit_size_id, r.status_id,
           r.on_month, r.c1, r.c2, r.c3, r.c4, r.c5, r.c6, r.c7, r.c8, r.c9, r.c10, r.c11, r.c12, r.c13, r.c14, r.c15,
           r.c16, r.c17, r.c18, r.c19, r.c20, r.sd, r.sem, r.sey
      FROM (
        SELECT unit_id, p_sign, unit_type, primary_activity_category_path, secondary_activity_category_path,
               sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
               count(*) FILTER (WHERE kind = 'exists_added_count')::int AS a,
               count(*) FILTER (WHERE kind = 'exists_removed_count')::int,
               count(*) FILTER (WHERE kind = 'countable_added_count')::int,
               count(*) FILTER (WHERE kind = 'countable_removed_count')::int,
               count(*) FILTER (WHERE kind = 'exists_moved_in_count')::int,
               count(*) FILTER (WHERE kind = 'exists_moved_out_count')::int,
               count(*) FILTER (WHERE kind = 'countable_moved_in_count')::int,
               count(*) FILTER (WHERE kind = 'countable_moved_out_count')::int,
               count(*) FILTER (WHERE kind = 'births')::int,
               count(*) FILTER (WHERE kind = 'deaths')::int,
               count(*) FILTER (WHERE kind = 'name_change_count')::int,
               count(*) FILTER (WHERE kind = 'primary_activity_category_change_count')::int,
               count(*) FILTER (WHERE kind = 'secondary_activity_category_change_count')::int,
               count(*) FILTER (WHERE kind = 'sector_change_count')::int,
               count(*) FILTER (WHERE kind = 'legal_form_change_count')::int,
               count(*) FILTER (WHERE kind = 'physical_region_change_count')::int,
               count(*) FILTER (WHERE kind = 'physical_country_change_count')::int,
               count(*) FILTER (WHERE kind = 'physical_address_change_count')::int,
               count(*) FILTER (WHERE kind = 'unit_size_change_count')::int,
               count(*) FILTER (WHERE kind = 'status_change_count')::int,
               public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(sd) FILTER (WHERE kind = 'stats_delta')) AS sd,
               public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(sd) FILTER (WHERE kind = 'stats_ended_month')) AS sem,
               public.jsonb_stats_delta_nullif_zero(public.jsonb_stats_delta_agg(sd) FILTER (WHERE kind = 'stats_ended_year')) AS sey,
               count(*) FILTER (WHERE n <> 0) AS events
          FROM pg_temp.hd_ev
         GROUP BY unit_id, unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path,
                  legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month
    ) AS r(unit_id, sign, unit_type, primary_activity_category_path, secondary_activity_category_path,
           sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month,
           c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19, c20, sd, sem, sey, events)
     WHERE r.events > 0 OR r.sd IS NOT NULL OR r.sem IS NOT NULL OR r.sey IS NOT NULL;
END;
$procedure$
```
