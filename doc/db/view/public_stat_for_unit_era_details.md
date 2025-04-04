```sql
                                 View "public.stat_for_unit_era"
       Column       |       Type        | Collation | Nullable | Default | Storage  | Description 
--------------------+-------------------+-----------+----------+---------+----------+-------------
 id                 | integer           |           |          |         | plain    | 
 stat_definition_id | integer           |           |          |         | plain    | 
 valid_after        | date              |           |          |         | plain    | 
 valid_from         | date              |           |          |         | plain    | 
 valid_to           | date              |           |          |         | plain    | 
 data_source_id     | integer           |           |          |         | plain    | 
 establishment_id   | integer           |           |          |         | plain    | 
 legal_unit_id      | integer           |           |          |         | plain    | 
 value_int          | integer           |           |          |         | plain    | 
 value_float        | double precision  |           |          |         | plain    | 
 value_string       | character varying |           |          |         | extended | 
 value_bool         | boolean           |           |          |         | plain    | 
View definition:
 SELECT id,
    stat_definition_id,
    valid_after,
    valid_from,
    valid_to,
    data_source_id,
    establishment_id,
    legal_unit_id,
    value_int,
    value_float,
    value_string,
    value_bool
   FROM stat_for_unit;
Triggers:
    stat_for_unit_era_upsert INSTEAD OF INSERT ON stat_for_unit_era FOR EACH ROW EXECUTE FUNCTION admin.stat_for_unit_era_upsert()
Options: security_invoker=on

```
