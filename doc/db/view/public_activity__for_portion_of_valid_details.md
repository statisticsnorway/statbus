```sql
                             View "public.activity__for_portion_of_valid"
      Column      |           Type           | Collation | Nullable | Default | Storage  | Description 
------------------+--------------------------+-----------+----------+---------+----------+-------------
 id               | integer                  |           |          |         | plain    | 
 valid_range      | daterange                |           |          |         | extended | 
 valid_from       | date                     |           |          |         | plain    | 
 valid_to         | date                     |           |          |         | plain    | 
 valid_until      | date                     |           |          |         | plain    | 
 type             | activity_type            |           |          |         | plain    | 
 category_id      | integer                  |           |          |         | plain    | 
 data_source_id   | integer                  |           |          |         | plain    | 
 edit_comment     | character varying(512)   |           |          |         | extended | 
 edit_by_user_id  | integer                  |           |          |         | plain    | 
 edit_at          | timestamp with time zone |           |          |         | plain    | 
 establishment_id | integer                  |           |          |         | plain    | 
 legal_unit_id    | integer                  |           |          |         | plain    | 
View definition:
 SELECT id,
    valid_range,
    valid_from,
    valid_to,
    valid_until,
    type,
    category_id,
    data_source_id,
    edit_comment,
    edit_by_user_id,
    edit_at,
    establishment_id,
    legal_unit_id
   FROM activity;
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON activity__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
