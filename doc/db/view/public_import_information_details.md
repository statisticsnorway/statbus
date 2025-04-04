```sql
                                      View "public.import_information"
         Column         |           Type           | Collation | Nullable | Default | Storage  | Description 
------------------------+--------------------------+-----------+----------+---------+----------+-------------
 job_id                 | integer                  |           |          |         | plain    | 
 definition_id          | integer                  |           |          |         | plain    | 
 import_job_slug        | text                     |           |          |         | extended | 
 import_definition_slug | text                     |           |          |         | extended | 
 import_name            | text                     |           |          |         | extended | 
 import_note            | text                     |           |          |         | extended | 
 target_schema_name     | text                     |           |          |         | extended | 
 upload_table_name      | text                     |           |          |         | extended | 
 data_table_name        | text                     |           |          |         | extended | 
 source_column          | text                     |           |          |         | extended | 
 source_value           | text                     |           |          |         | extended | 
 source_expression      | import_source_expression |           |          |         | plain    | 
 target_column          | text                     |           |          |         | extended | 
 target_type            | text                     |           |          |         | extended | 
 uniquely_identifying   | boolean                  |           |          |         | plain    | 
 source_column_priority | integer                  |           |          |         | plain    | 
View definition:
 SELECT ij.id AS job_id,
    id.id AS definition_id,
    ij.slug AS import_job_slug,
    id.slug AS import_definition_slug,
    id.name AS import_name,
    id.note AS import_note,
    it.schema_name AS target_schema_name,
    ij.upload_table_name,
    ij.data_table_name,
    isc.column_name AS source_column,
    im.source_value,
    im.source_expression,
    itc.column_name AS target_column,
    itc.column_type AS target_type,
    itc.uniquely_identifying,
    isc.priority AS source_column_priority
   FROM import_job ij
     JOIN import_definition id ON ij.definition_id = id.id
     JOIN import_target it ON id.target_id = it.id
     JOIN import_mapping im ON id.id = im.definition_id
     LEFT JOIN import_source_column isc ON im.source_column_id = isc.id
     LEFT JOIN import_target_column itc ON im.target_column_id = itc.id
  ORDER BY id.id, ij.id, isc.priority, isc.id, itc.id;
Options: security_barrier=true

```
