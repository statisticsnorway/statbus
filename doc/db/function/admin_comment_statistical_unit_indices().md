```sql
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
$function$
```
