```sql
                           View "public.external_ident_type_ordered"
   Column    |          Type          | Collation | Nullable | Default | Storage  | Description 
-------------+------------------------+-----------+----------+---------+----------+-------------
 id          | integer                |           |          |         | plain    | 
 code        | character varying(128) |           |          |         | extended | 
 name        | character varying(50)  |           |          |         | extended | 
 by_tag_id   | integer                |           |          |         | plain    | 
 description | text                   |           |          |         | extended | 
 priority    | integer                |           |          |         | plain    | 
 archived    | boolean                |           |          |         | plain    | 
View definition:
 SELECT id,
    code,
    name,
    by_tag_id,
    description,
    priority,
    archived
   FROM external_ident_type
  ORDER BY priority, code;

```
