```sql
                                  View "public.primary_establishment_activity_differs_def"
                   Column                   |         Type          | Collation | Nullable | Default | Storage | Description 
--------------------------------------------+-----------------------+-----------+----------+---------+---------+-------------
 unit_type                                  | statistical_unit_type |           |          |         | plain   | 
 unit_id                                    | integer               |           |          |         | plain   | 
 valid_from                                 | date                  |           |          |         | plain   | 
 valid_until                                | date                  |           |          |         | plain   | 
 legal_unit_activity_category_id            | integer               |           |          |         | plain   | 
 primary_establishment_id                   | integer               |           |          |         | plain   | 
 primary_establishment_activity_category_id | integer               |           |          |         | plain   | 
View definition:
 SELECT su.unit_type,
    su.unit_id,
    su.valid_from,
    su.valid_until,
    su.primary_activity_category_id AS legal_unit_activity_category_id,
    te.unit_id AS primary_establishment_id,
    te.primary_activity_category_id AS primary_establishment_activity_category_id
   FROM statistical_unit su
     JOIN timeline_establishment te ON te.legal_unit_id = su.unit_id AND te.primary_for_legal_unit AND te.valid_from <= su.valid_from AND su.valid_from < te.valid_until
  WHERE su.unit_type = 'legal_unit'::statistical_unit_type AND su.primary_activity_category_id IS DISTINCT FROM te.primary_activity_category_id;
Options: security_invoker=on

```

**Comment:** The rule of public.primary_establishment_activity_differs, read from statistical_unit and timeline_establishment.
