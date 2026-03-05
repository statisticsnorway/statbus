```sql
                               View "public.power_group_active"
   Column   |          Type          | Collation | Nullable | Default | Storage  | Description 
------------+------------------------+-----------+----------+---------+----------+-------------
 id         | integer                |           |          |         | plain    | 
 ident      | text                   |           |          |         | extended | 
 short_name | character varying(16)  |           |          |         | extended | 
 name       | character varying(256) |           |          |         | extended | 
 type_id    | integer                |           |          |         | plain    | 
View definition:
 SELECT DISTINCT pg.id,
    pg.ident,
    pg.short_name,
    pg.name,
    pg.type_id
   FROM power_group pg
     JOIN legal_relationship lr ON lr.derived_power_group_id = pg.id
  WHERE lr.valid_range @> CURRENT_DATE;
Options: security_invoker=on

```
