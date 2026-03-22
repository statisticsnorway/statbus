```sql
                      View "public.import_source_column_type"
     Column     |  Type   | Collation | Nullable | Default | Storage  | Description 
----------------+---------+-----------+----------+---------+----------+-------------
 definition_id  | integer |           |          |         | plain    | 
 column_name    | text    |           |          |         | extended | 
 priority       | integer |           |          |         | plain    | 
 target_pg_type | text    |           |          |         | extended | 
View definition:
 SELECT isc.definition_id,
    isc.column_name,
    isc.priority,
    COALESCE(idc.target_pg_type, 'TEXT'::text) AS target_pg_type
   FROM import_source_column isc
     LEFT JOIN import_mapping im ON im.source_column_id = isc.id AND NOT im.is_ignored
     LEFT JOIN import_data_column idc ON idc.id = im.target_data_column_id;
Options: security_invoker=on

```
