```sql
                        View "public.time_context"
     Column      |         Type          | Collation | Nullable | Default 
-----------------+-----------------------+-----------+----------+---------
 type            | time_context_type     |           |          | 
 ident           | text                  |           |          | 
 name_when_query | character varying     |           |          | 
 name_when_input | character varying     |           |          | 
 scope           | relative_period_scope |           |          | 
 valid_from      | date                  |           |          | 
 valid_to        | date                  |           |          | 
 valid_on        | date                  |           |          | 
 code            | relative_period_code  |           |          | 
 path            | ltree                 |           |          | 

```
