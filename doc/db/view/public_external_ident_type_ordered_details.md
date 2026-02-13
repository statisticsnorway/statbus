```sql
                           View "public.external_ident_type_ordered"
   Column    |          Type          | Collation | Nullable | Default | Storage  | Description 
-------------+------------------------+-----------+----------+---------+----------+-------------
 id          | integer                |           |          |         | plain    | 
 code        | character varying(128) |           |          |         | extended | 
 name        | character varying(50)  |           |          |         | extended | 
 shape       | external_ident_shape   |           |          |         | plain    | 
 labels      | ltree                  |           |          |         | extended | 
 description | text                   |           |          |         | extended | 
 priority    | integer                |           |          |         | plain    | 
 enabled     | boolean                |           |          |         | plain    | 
View definition:
 SELECT id,
    code,
    name,
    shape,
    labels,
    description,
    priority,
    enabled
   FROM external_ident_type
  ORDER BY priority, code;

```
