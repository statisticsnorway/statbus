```sql
               View "public.external_ident_type_ordered"
   Column    |          Type          | Collation | Nullable | Default 
-------------+------------------------+-----------+----------+---------
 id          | integer                |           |          | 
 code        | character varying(128) |           |          | 
 name        | character varying(50)  |           |          | 
 shape       | external_ident_shape   |           |          | 
 labels      | ltree                  |           |          | 
 description | text                   |           |          | 
 priority    | integer                |           |          | 
 archived    | boolean                |           |          | 

```
