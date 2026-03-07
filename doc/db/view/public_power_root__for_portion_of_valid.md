```sql
                     View "public.power_root__for_portion_of_valid"
           Column           |           Type           | Collation | Nullable | Default 
----------------------------+--------------------------+-----------+----------+---------
 id                         | integer                  |           |          | 
 power_group_id             | integer                  |           |          | 
 derived_root_legal_unit_id | integer                  |           |          | 
 derived_root_status        | power_group_root_status  |           |          | 
 custom_root_legal_unit_id  | integer                  |           |          | 
 root_legal_unit_id         | integer                  |           |          | 
 valid_range                | daterange                |           |          | 
 valid_from                 | date                     |           |          | 
 valid_to                   | date                     |           |          | 
 valid_until                | date                     |           |          | 
 edit_comment               | character varying(512)   |           |          | 
 edit_by_user_id            | integer                  |           |          | 
 edit_at                    | timestamp with time zone |           |          | 
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON power_root__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
