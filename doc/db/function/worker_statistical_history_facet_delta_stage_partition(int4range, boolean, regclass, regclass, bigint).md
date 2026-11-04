```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_stage_partition(IN p_hash_range int4range, IN p_rebuild boolean, IN p_old regclass DEFAULT 'statistical_unit'::regclass, IN p_new regclass DEFAULT 'statistical_unit_staging'::regclass, IN p_generation bigint DEFAULT 0)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    CALL worker.statistical_history_facet_delta_contribution_begin();
    IF to_regclass('pg_temp.hd_units') IS NOT NULL THEN DROP TABLE pg_temp.hd_units; END IF;
    IF to_regclass('pg_temp.hd_refreshed') IS NOT NULL THEN DROP TABLE pg_temp.hd_refreshed; END IF;
    EXECUTE format($SQL$CREATE TEMP TABLE hd_refreshed AS SELECT DISTINCT unit_type, unit_id FROM %1$s
                        WHERE %2$L <= hash_slot AND hash_slot < %3$L$SQL$, p_new, lower(p_hash_range), upper(p_hash_range));
    IF p_rebuild THEN
        EXECUTE format($SQL$CREATE TEMP TABLE hd_units AS
                            SELECT DISTINCT o.unit_type, o.unit_id FROM %1$s AS o
                             WHERE %2$L <= o.hash_slot AND o.hash_slot < %3$L
                               AND NOT EXISTS (SELECT 1 FROM pg_temp.hd_refreshed AS r
                                                WHERE r.unit_type = o.unit_type AND r.unit_id = o.unit_id)$SQL$,
                       p_old, lower(p_hash_range), upper(p_hash_range));
        CALL worker.statistical_history_facet_delta_contribution(p_old, 1::smallint);
        DROP TABLE pg_temp.hd_units;
        CREATE TEMP TABLE hd_units AS SELECT * FROM pg_temp.hd_refreshed;
        CALL worker.statistical_history_facet_delta_contribution(p_new, 1::smallint);
    ELSE
        CREATE TEMP TABLE hd_units AS SELECT * FROM pg_temp.hd_refreshed;
        CALL worker.statistical_history_facet_delta_contribution(p_old, (-1)::smallint);
        CALL worker.statistical_history_facet_delta_contribution(p_new, 1::smallint);
    END IF;
    CALL worker.statistical_history_facet_delta_contribution_stage(p_generation);
END;
$procedure$
```
