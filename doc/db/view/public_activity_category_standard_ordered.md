```sql
                             View "public.activity_category_standard_ordered"
    Column    |               Type               | Collation | Nullable | Default | Storage  | Description 
--------------+----------------------------------+-----------+----------+---------+----------+-------------
 id           | integer                          |           |          |         | plain    | 
 code         | character varying(16)            |           |          |         | extended | 
 name         | character varying                |           |          |         | extended | 
 description  | character varying                |           |          |         | extended | 
 code_pattern | activity_category_code_behaviour |           |          |         | plain    | 
 enabled      | boolean                          |           |          |         | plain    | 
 lasts_to     | date                             |           |          |         | plain    | 
View definition:
 SELECT id,
    code,
    name,
    description,
    code_pattern,
    enabled,
    lasts_to
   FROM activity_category_standard
  ORDER BY code;
Options: security_invoker=on

```
