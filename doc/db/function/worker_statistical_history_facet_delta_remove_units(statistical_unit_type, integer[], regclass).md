```sql
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_delta_remove_units(IN p_unit_type statistical_unit_type, IN p_unit_ids integer[], IN p_old regclass DEFAULT 'statistical_unit'::regclass)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    CALL worker.statistical_history_facet_delta_contribution_begin();
    IF to_regclass('pg_temp.hd_units') IS NOT NULL THEN DROP TABLE pg_temp.hd_units; END IF;
    CREATE TEMP TABLE hd_units AS SELECT p_unit_type AS unit_type, id AS unit_id FROM unnest(p_unit_ids) AS id;
    CALL worker.statistical_history_facet_delta_contribution(p_old, (-1)::smallint);
    CALL worker.statistical_history_facet_delta_contribution_stage(0);
END;
$procedure$
```
