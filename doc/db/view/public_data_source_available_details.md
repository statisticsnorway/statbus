```sql
                               View "public.data_source_available"
   Column   |           Type           | Collation | Nullable | Default | Storage  | Description 
------------+--------------------------+-----------+----------+---------+----------+-------------
 id         | integer                  |           |          |         | plain    | 
 code       | text                     |           |          |         | extended | 
 name       | text                     |           |          |         | extended | 
 active     | boolean                  |           |          |         | plain    | 
 custom     | boolean                  |           |          |         | plain    | 
 updated_at | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT data_source_ordered.id,
    data_source_ordered.code,
    data_source_ordered.name,
    data_source_ordered.active,
    data_source_ordered.custom,
    data_source_ordered.updated_at
   FROM data_source_ordered
  WHERE data_source_ordered.active;
Options: security_invoker=on

```
