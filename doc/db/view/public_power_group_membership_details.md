```sql
                          View "public.power_group_membership"
      Column       |   Type    | Collation | Nullable | Default | Storage  | Description 
-------------------+-----------+-----------+----------+---------+----------+-------------
 power_group_id    | integer   |           |          |         | plain    | 
 power_group_ident | text      |           |          |         | extended | 
 legal_unit_id     | integer   |           |          |         | plain    | 
 power_level       | integer   |           |          |         | plain    | 
 valid_range       | daterange |           |          |         | extended | 
View definition:
 SELECT DISTINCT lr.derived_power_group_id AS power_group_id,
    pg.ident AS power_group_ident,
    lr.influencing_id AS legal_unit_id,
    1 AS power_level,
    lr.valid_range
   FROM legal_relationship lr
     JOIN power_group pg ON pg.id = lr.derived_power_group_id
  WHERE lr.derived_power_group_id IS NOT NULL AND NOT (EXISTS ( SELECT 1
           FROM legal_relationship lr2
          WHERE lr2.influenced_id = lr.influencing_id AND lr2.derived_power_group_id = lr.derived_power_group_id AND lr2.valid_range && lr.valid_range))
UNION
 SELECT lr.derived_power_group_id AS power_group_id,
    pg.ident AS power_group_ident,
    lr.influenced_id AS legal_unit_id,
    lr.derived_influenced_power_level AS power_level,
    lr.valid_range
   FROM legal_relationship lr
     JOIN power_group pg ON pg.id = lr.derived_power_group_id
  WHERE lr.derived_power_group_id IS NOT NULL AND lr.derived_influenced_power_level IS NOT NULL;
Options: security_invoker=on

```
