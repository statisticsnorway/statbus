```sql
                                  View "public.sector_available"
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
 SELECT sector_ordered.id,
    sector_ordered.path,
    sector_ordered.parent_id,
    sector_ordered.label,
    sector_ordered.code,
    sector_ordered.name,
    sector_ordered.description,
    sector_ordered.active,
    sector_ordered.custom,
    sector_ordered.updated_at
   FROM sector_ordered
  WHERE sector_ordered.active;
Options: security_invoker=on

```
