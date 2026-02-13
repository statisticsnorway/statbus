```sql
                           View "public.stat_definition_active"
   Column    |       Type        | Collation | Nullable | Default | Storage  | Description 
-------------+-------------------+-----------+----------+---------+----------+-------------
 id          | integer           |           |          |         | plain    | 
 code        | character varying |           |          |         | extended | 
 type        | stat_type         |           |          |         | plain    | 
 frequency   | stat_frequency    |           |          |         | plain    | 
 name        | character varying |           |          |         | extended | 
 description | text              |           |          |         | extended | 
 priority    | integer           |           |          |         | plain    | 
 enabled     | boolean           |           |          |         | plain    | 
View definition:
 SELECT id,
    code,
    type,
    frequency,
    name,
    description,
    priority,
    enabled
   FROM stat_definition_ordered
  WHERE enabled;

```
