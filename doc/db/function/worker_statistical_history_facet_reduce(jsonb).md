```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    RAISE DEBUG 'statistical_history_facet_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- Drop indexes before bulk insert (18 indexes on 287K+ rows costs 15s to maintain
    -- row-by-row; dropping and recreating after is ~11s total including index build).
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_year;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_month;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_unit_type;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_primary_activity_category_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_primary_activity_category_pa;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_secondary_activity_category_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_secondary_activity_category_;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_sector_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_sector_path;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_legal_form_id;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_region_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_physical_region_path;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_country_id;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_stats_summary;
    DROP INDEX IF EXISTS public.statistical_history_facet_month_key;
    DROP INDEX IF EXISTS public.statistical_history_facet_year_key;

    -- TRUNCATE is instant (no dead tuples, no per-row WAL), unlike DELETE which
    -- accumulates ~800K dead tuples per cycle causing progressive slowdown.
    TRUNCATE public.statistical_history_facet;

    -- Aggregate from UNLOGGED partition table into main LOGGED table
    INSERT INTO public.statistical_history_facet (
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count,
        physical_country_change_count, physical_address_change_count,
        unit_size_change_count, status_change_count,
        stats_summary
    )
    SELECT
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        SUM(exists_count)::integer, SUM(exists_change)::integer,
        SUM(exists_added_count)::integer, SUM(exists_removed_count)::integer,
        SUM(countable_count)::integer, SUM(countable_change)::integer,
        SUM(countable_added_count)::integer, SUM(countable_removed_count)::integer,
        SUM(births)::integer, SUM(deaths)::integer,
        SUM(name_change_count)::integer, SUM(primary_activity_category_change_count)::integer,
        SUM(secondary_activity_category_change_count)::integer, SUM(sector_change_count)::integer,
        SUM(legal_form_change_count)::integer, SUM(physical_region_change_count)::integer,
        SUM(physical_country_change_count)::integer, SUM(physical_address_change_count)::integer,
        SUM(unit_size_change_count)::integer, SUM(status_change_count)::integer,
        jsonb_stats_merge_agg(stats_summary)
    FROM public.statistical_history_facet_partitions
    GROUP BY resolution, year, month, unit_type,
             primary_activity_category_path, secondary_activity_category_path,
             sector_path, legal_form_id, physical_region_path,
             physical_country_id, unit_size_id, status_id;

    -- Recreate indexes after bulk insert
    CREATE UNIQUE INDEX statistical_history_facet_month_key
        ON public.statistical_history_facet (resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path, physical_country_id)
        WHERE resolution = 'year-month'::public.history_resolution;
    CREATE UNIQUE INDEX statistical_history_facet_year_key
        ON public.statistical_history_facet (year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path, physical_country_id)
        WHERE resolution = 'year'::public.history_resolution;
    CREATE INDEX idx_statistical_history_facet_year ON public.statistical_history_facet (year);
    CREATE INDEX idx_statistical_history_facet_month ON public.statistical_history_facet (month);
    CREATE INDEX idx_statistical_history_facet_unit_type ON public.statistical_history_facet (unit_type);
    CREATE INDEX idx_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet (primary_activity_category_path);
    CREATE INDEX idx_gist_statistical_history_facet_primary_activity_category_pa ON public.statistical_history_facet USING GIST (primary_activity_category_path);
    CREATE INDEX idx_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet (secondary_activity_category_path);
    CREATE INDEX idx_gist_statistical_history_facet_secondary_activity_category_ ON public.statistical_history_facet USING GIST (secondary_activity_category_path);
    CREATE INDEX idx_statistical_history_facet_sector_path ON public.statistical_history_facet (sector_path);
    CREATE INDEX idx_gist_statistical_history_facet_sector_path ON public.statistical_history_facet USING GIST (sector_path);
    CREATE INDEX idx_statistical_history_facet_legal_form_id ON public.statistical_history_facet (legal_form_id);
    CREATE INDEX idx_statistical_history_facet_physical_region_path ON public.statistical_history_facet (physical_region_path);
    CREATE INDEX idx_gist_statistical_history_facet_physical_region_path ON public.statistical_history_facet USING GIST (physical_region_path);
    CREATE INDEX idx_statistical_history_facet_physical_country_id ON public.statistical_history_facet (physical_country_id);
    CREATE INDEX idx_statistical_history_facet_stats_summary ON public.statistical_history_facet USING GIN (stats_summary jsonb_path_ops);

    RAISE DEBUG 'statistical_history_facet_reduce: done';
END;
$procedure$
```
