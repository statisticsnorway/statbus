```sql
                                View "public.legal_form_ordered"
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
 SELECT legal_form.id,
    legal_form.code,
    legal_form.name,
    legal_form.active,
    legal_form.custom,
    legal_form.created_at,
    legal_form.updated_at
   FROM legal_form
  ORDER BY legal_form.code;
Options: security_invoker=on

```
