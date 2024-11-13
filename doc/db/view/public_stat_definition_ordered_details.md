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
 SELECT stat_definition.id,
    stat_definition.code,
    stat_definition.type,
    stat_definition.frequency,
    stat_definition.name,
    stat_definition.description,
    stat_definition.priority,
    stat_definition.archived
   FROM stat_definition
  ORDER BY stat_definition.priority, stat_definition.code;

```
