```sql
                                   View "public.sector_ordered"
   Column    |           Type           | Collation | Nullable | Default | Storage  | Description 
-------------+--------------------------+-----------+----------+---------+----------+-------------
 id          | integer                  |           |          |         | plain    | 
 path        | ltree                    |           |          |         | extended | 
 parent_id   | integer                  |           |          |         | plain    | 
 label       | character varying        |           |          |         | extended | 
 code        | character varying        |           |          |         | extended | 
 name        | text                     |           |          |         | extended | 
 description | text                     |           |          |         | extended | 
 active      | boolean                  |           |          |         | plain    | 
 custom      | boolean                  |           |          |         | plain    | 
 updated_at  | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT sector.id,
    sector.path,
    sector.parent_id,
    sector.label,
    sector.code,
    sector.name,
    sector.description,
    sector.active,
    sector.custom,
    sector.updated_at
   FROM sector
  ORDER BY sector.path;
Options: security_invoker=on

```
