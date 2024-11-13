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
 archived    | boolean           |           |          |         | plain    | 
View definition:
 SELECT stat_definition_ordered.id,
    stat_definition_ordered.code,
    stat_definition_ordered.type,
    stat_definition_ordered.frequency,
    stat_definition_ordered.name,
    stat_definition_ordered.description,
    stat_definition_ordered.priority,
    stat_definition_ordered.archived
   FROM stat_definition_ordered
  WHERE NOT stat_definition_ordered.archived;

```
