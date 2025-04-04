```sql
                           View "public.stat_definition_ordered"
   Column    |       Type        | Collation | Nullable | Default | Storage  | Description 
-------------+-------------------+-----------+----------+---------+----------+-------------
 id          | integer           |           |          |         | plain    | 
 code        | character varying |           |          |         | extended | 
 type        | stat_type         |           |          |         | plain    | 
 frequency   | stat_frequency    |           |          |         | plain    | 
 name        | character varying |           |          |         | extended | 
 description | text              |           |          |         | extended | 
 priority    | integer           |           |          |         | plain    | 
 archived    | boolean           |           |          |         | plain    | 
View definition:
 SELECT id,
    code,
    type,
    frequency,
    name,
    description,
    priority,
    archived
   FROM stat_definition
  ORDER BY priority, code;

```
