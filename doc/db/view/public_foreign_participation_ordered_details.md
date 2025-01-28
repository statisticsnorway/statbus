```sql
                           View "public.foreign_participation_ordered"
   Column   |           Type           | Collation | Nullable | Default | Storage  | Description 
------------+--------------------------+-----------+----------+---------+----------+-------------
 id         | integer                  |           |          |         | plain    | 
 code       | text                     |           |          |         | extended | 
 name       | text                     |           |          |         | extended | 
 active     | boolean                  |           |          |         | plain    | 
 custom     | boolean                  |           |          |         | plain    | 
 created_at | timestamp with time zone |           |          |         | plain    | 
 updated_at | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT foreign_participation.id,
    foreign_participation.code,
    foreign_participation.name,
    foreign_participation.active,
    foreign_participation.custom,
    foreign_participation.created_at,
    foreign_participation.updated_at
   FROM foreign_participation
  ORDER BY foreign_participation.code;
Options: security_invoker=on

```
