```sql
                     View "public.stat_for_unit_era"
       Column       |       Type        | Collation | Nullable | Default 
--------------------+-------------------+-----------+----------+---------
 id                 | integer           |           |          | 
 stat_definition_id | integer           |           |          | 
 valid_after        | date              |           |          | 
 valid_from         | date              |           |          | 
 valid_to           | date              |           |          | 
 data_source_id     | integer           |           |          | 
 establishment_id   | integer           |           |          | 
 legal_unit_id      | integer           |           |          | 
 value_int          | integer           |           |          | 
 value_float        | double precision  |           |          | 
 value_string       | character varying |           |          | 
 value_bool         | boolean           |           |          | 
Triggers:
    stat_for_unit_era_upsert INSTEAD OF INSERT ON stat_for_unit_era FOR EACH ROW EXECUTE FUNCTION admin.stat_for_unit_era_upsert()

```
