```sql
                                        View "public.tag_enabled"
       Column        |           Type           | Collation | Nullable | Default | Storage  | Description 
---------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                  | integer                  |           |          |         | plain    | 
 path                | ltree                    |           |          |         | extended | 
 parent_id           | integer                  |           |          |         | plain    | 
 level               | integer                  |           |          |         | plain    | 
 label               | character varying        |           |          |         | extended | 
 code                | character varying        |           |          |         | extended | 
 name                | character varying(256)   |           |          |         | extended | 
 description         | text                     |           |          |         | extended | 
 enabled             | boolean                  |           |          |         | plain    | 
 context_valid_from  | date                     |           |          |         | plain    | 
 context_valid_to    | date                     |           |          |         | plain    | 
 context_valid_until | date                     |           |          |         | plain    | 
 context_valid_on    | date                     |           |          |         | plain    | 
 created_at          | timestamp with time zone |           |          |         | plain    | 
 updated_at          | timestamp with time zone |           |          |         | plain    | 
 custom              | boolean                  |           |          |         | plain    | 
View definition:
 SELECT id,
    path,
    parent_id,
    level,
    label,
    code,
    name,
    description,
    enabled,
    context_valid_from,
    context_valid_to,
    context_valid_until,
    context_valid_on,
    created_at,
    updated_at,
    custom
   FROM tag_ordered
  WHERE enabled;
Options: security_invoker=on

```
