```sql
                            View "public.external_ident_type_active"
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
 SELECT external_ident_type_ordered.id,
    external_ident_type_ordered.code,
    external_ident_type_ordered.name,
    external_ident_type_ordered.by_tag_id,
    external_ident_type_ordered.description,
    external_ident_type_ordered.priority,
    external_ident_type_ordered.archived
   FROM external_ident_type_ordered
  WHERE NOT external_ident_type_ordered.archived;

```