```sql
                               View "public.legal_form_available"
   Column   |           Type           | Collation | Nullable | Default | Storage  | Description 
------------+--------------------------+-----------+----------+---------+----------+-------------
 id         | integer                  |           |          |         | plain    | 
 code       | text                     |           |          |         | extended | 
 name       | text                     |           |          |         | extended | 
 active     | boolean                  |           |          |         | plain    | 
 custom     | boolean                  |           |          |         | plain    | 
 updated_at | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT legal_form_ordered.id,
    legal_form_ordered.code,
    legal_form_ordered.name,
    legal_form_ordered.active,
    legal_form_ordered.custom,
    legal_form_ordered.updated_at
   FROM legal_form_ordered
  WHERE legal_form_ordered.active;
Options: security_invoker=on

```
