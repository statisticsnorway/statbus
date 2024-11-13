```sql
                                View "public.data_source_ordered"
   Column   |           Type           | Collation | Nullable | Default | Storage  | Description 
------------+--------------------------+-----------+----------+---------+----------+-------------
 id         | integer                  |           |          |         | plain    | 
 code       | text                     |           |          |         | extended | 
 name       | text                     |           |          |         | extended | 
 active     | boolean                  |           |          |         | plain    | 
 custom     | boolean                  |           |          |         | plain    | 
 updated_at | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT data_source.id,
    data_source.code,
    data_source.name,
    data_source.active,
    data_source.custom,
    data_source.updated_at
   FROM data_source
  ORDER BY data_source.code;
Options: security_invoker=on

```
