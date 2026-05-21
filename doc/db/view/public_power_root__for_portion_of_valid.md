```sql
                                 View "public.power_root__for_portion_of_valid"
           Column           |           Type           | Collation | Nullable | Default | Storage  | Description 
----------------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                         | integer                  |           |          |         | plain    | 
 power_group_id             | integer                  |           |          |         | plain    | 
 derived_root_legal_unit_id | integer                  |           |          |         | plain    | 
 derived_root_status        | power_group_root_status  |           |          |         | plain    | 
 custom_root_legal_unit_id  | integer                  |           |          |         | plain    | 
 root_legal_unit_id         | integer                  |           |          |         | plain    | 
 valid_range                | daterange                |           |          |         | extended | 
 valid_from                 | date                     |           |          |         | plain    | 
 valid_to                   | date                     |           |          |         | plain    | 
 valid_until                | date                     |           |          |         | plain    | 
 edit_comment               | character varying(512)   |           |          |         | extended | 
 edit_by_user_id            | integer                  |           |          |         | plain    | 
 edit_at                    | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    power_group_id,
    derived_root_legal_unit_id,
    derived_root_status,
    custom_root_legal_unit_id,
    root_legal_unit_id,
    valid_range,
    valid_from,
    valid_to,
    valid_until,
    edit_comment,
    edit_by_user_id,
    edit_at
   FROM power_root;
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON power_root__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')
Options: security_invoker=on

```
