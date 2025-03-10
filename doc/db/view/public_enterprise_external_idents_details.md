```sql
                             View "public.enterprise_external_idents"
     Column      |         Type          | Collation | Nullable | Default | Storage  | Description 
-----------------+-----------------------+-----------+----------+---------+----------+-------------
 unit_type       | statistical_unit_type |           |          |         | plain    | 
 unit_id         | integer               |           |          |         | plain    | 
 external_idents | jsonb                 |           |          |         | extended | 
 valid_after     | date                  |           |          |         | plain    | 
 valid_to        | date                  |           |          |         | plain    | 
View definition:
 SELECT 'enterprise'::statistical_unit_type AS unit_type,
    plu.enterprise_id AS unit_id,
    get_external_idents('legal_unit'::statistical_unit_type, plu.id) AS external_idents,
    plu.valid_after,
    plu.valid_to
   FROM legal_unit plu
  WHERE plu.primary_for_enterprise = true
UNION ALL
 SELECT 'enterprise'::statistical_unit_type AS unit_type,
    pes.enterprise_id AS unit_id,
    get_external_idents('establishment'::statistical_unit_type, pes.id) AS external_idents,
    pes.valid_after,
    pes.valid_to
   FROM establishment pes
  WHERE pes.enterprise_id IS NOT NULL;

```
