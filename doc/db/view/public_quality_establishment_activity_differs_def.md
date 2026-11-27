```sql
                               View "public.quality_establishment_activity_differs_def"
               Column               |         Type          | Collation | Nullable | Default | Storage  | Description 
------------------------------------+-----------------------+-----------+----------+---------+----------+-------------
 check_id                           | integer               |           |          |         | plain    | 
 unit_type                          | statistical_unit_type |           |          |         | plain    | 
 unit_id                            | integer               |           |          |         | plain    | 
 valid_range                        | daterange             |           |          |         | extended | 
 existence_from                     | date                  |           |          |         | plain    | 
 existence_until                    | date                  |           |          |         | plain    | 
 hash_slot                          | integer               |           |          |         | plain    | 
 primary_establishment_id           | integer               |           |          |         | plain    | 
 legal_unit_activity_category_id    | integer               |           |          |         | plain    | 
 establishment_activity_category_id | integer               |           |          |         | plain    | 
View definition:
 SELECT 4 AS check_id,
    su.unit_type,
    su.unit_id,
    su.valid_range,
    existence_from(su.*) AS existence_from,
    existence_until(su.*) AS existence_until,
    su.hash_slot,
    te.unit_id AS primary_establishment_id,
    su.primary_activity_category_id AS legal_unit_activity_category_id,
    te.primary_activity_category_id AS establishment_activity_category_id
   FROM statistical_unit su
     JOIN timeline_establishment te ON te.legal_unit_id = su.unit_id AND te.primary_for_legal_unit AND te.valid_from <= su.valid_from AND su.valid_from < te.valid_until
  WHERE su.unit_type = 'legal_unit'::statistical_unit_type AND su.primary_activity_category_id IS DISTINCT FROM te.primary_activity_category_id;
Options: security_invoker=on

```

**Comment:** The rule of check 4, establishment_activity_differs (xz3jej): a legal unit's statistical_unit row whose primary establishment, at the row's start, has another primary activity category (either may have none). Its columns are those of public.quality_establishment_activity_differs, which public.quality_relation_derive fills from it per hash partition.
