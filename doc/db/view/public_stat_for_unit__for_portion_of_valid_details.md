```sql
                            View "public.stat_for_unit__for_portion_of_valid"
       Column       |           Type           | Collation | Nullable | Default | Storage  | Description 
--------------------+--------------------------+-----------+----------+---------+----------+-------------
 id                 | integer                  |           |          |         | plain    | 
 stat_definition_id | integer                  |           |          |         | plain    | 
 valid_from         | date                     |           |          |         | plain    | 
 valid_to           | date                     |           |          |         | plain    | 
 valid_until        | date                     |           |          |         | plain    | 
 data_source_id     | integer                  |           |          |         | plain    | 
 establishment_id   | integer                  |           |          |         | plain    | 
 legal_unit_id      | integer                  |           |          |         | plain    | 
 value_int          | integer                  |           |          |         | plain    | 
 value_float        | double precision         |           |          |         | plain    | 
 value_string       | character varying        |           |          |         | extended | 
 value_bool         | boolean                  |           |          |         | plain    | 
 created_at         | timestamp with time zone |           |          |         | plain    | 
 edit_comment       | character varying(512)   |           |          |         | extended | 
 edit_by_user_id    | integer                  |           |          |         | plain    | 
 edit_at            | timestamp with time zone |           |          |         | plain    | 
View definition:
 SELECT id,
    stat_definition_id,
    valid_from,
    valid_to,
    valid_until,
    data_source_id,
    establishment_id,
    legal_unit_id,
    value_int,
    value_float,
    value_string,
    value_bool,
    created_at,
    edit_comment,
    edit_by_user_id,
    edit_at
   FROM stat_for_unit;
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON stat_for_unit__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
