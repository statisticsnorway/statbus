```sql
               View "public.stat_for_unit__for_portion_of_valid"
       Column       |           Type           | Collation | Nullable | Default 
--------------------+--------------------------+-----------+----------+---------
 id                 | integer                  |           |          | 
 stat_definition_id | integer                  |           |          | 
 valid_from         | date                     |           |          | 
 valid_to           | date                     |           |          | 
 valid_until        | date                     |           |          | 
 data_source_id     | integer                  |           |          | 
 establishment_id   | integer                  |           |          | 
 legal_unit_id      | integer                  |           |          | 
 value_int          | integer                  |           |          | 
 value_float        | double precision         |           |          | 
 value_string       | character varying        |           |          | 
 value_bool         | boolean                  |           |          | 
 created_at         | timestamp with time zone |           |          | 
 edit_comment       | character varying(512)   |           |          | 
 edit_by_user_id    | integer                  |           |          | 
 edit_at            | timestamp with time zone |           |          | 
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON stat_for_unit__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
