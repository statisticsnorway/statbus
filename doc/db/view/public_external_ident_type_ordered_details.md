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
 SELECT external_ident_type.id,
    external_ident_type.code,
    external_ident_type.name,
    external_ident_type.by_tag_id,
    external_ident_type.description,
    external_ident_type.priority,
    external_ident_type.archived
   FROM external_ident_type
  ORDER BY external_ident_type.priority, external_ident_type.code;

```
