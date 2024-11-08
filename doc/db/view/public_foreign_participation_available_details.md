```sql
                          View "public.foreign_participation_available"
   Column   |           Type           | Collation | Nullable | Default | Storage  | Description 
------------+--------------------------+-----------+----------+---------+----------+-------------
 id         | integer                  |           |          |         | plain    | 
 code       | text                     |           |          |         | extended | 
 name       | text                     |           |          |         | extended | 
 active     | boolean                  |           |          |         | plain    | 
 custom     | boolean                  |           |          |         | plain    | 
 updated_at | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT foreign_participation_ordered.id,
    foreign_participation_ordered.code,
    foreign_participation_ordered.name,
    foreign_participation_ordered.active,
    foreign_participation_ordered.custom,
    foreign_participation_ordered.updated_at
   FROM foreign_participation_ordered
  WHERE foreign_participation_ordered.active;
Options: security_invoker=on

```
