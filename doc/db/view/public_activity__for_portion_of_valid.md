```sql
                 View "public.activity__for_portion_of_valid"
      Column      |           Type           | Collation | Nullable | Default 
------------------+--------------------------+-----------+----------+---------
 id               | integer                  |           |          | 
 valid_range      | daterange                |           |          | 
 valid_from       | date                     |           |          | 
 valid_to         | date                     |           |          | 
 valid_until      | date                     |           |          | 
 type             | activity_type            |           |          | 
 category_id      | integer                  |           |          | 
 data_source_id   | integer                  |           |          | 
 edit_comment     | character varying(512)   |           |          | 
 edit_by_user_id  | integer                  |           |          | 
 edit_at          | timestamp with time zone |           |          | 
 establishment_id | integer                  |           |          | 
 legal_unit_id    | integer                  |           |          | 
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON activity__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
