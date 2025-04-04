```sql
                          View "public.import_information"
         Column         |           Type           | Collation | Nullable | Default 
------------------------+--------------------------+-----------+----------+---------
 job_id                 | integer                  |           |          | 
 definition_id          | integer                  |           |          | 
 import_job_slug        | text                     |           |          | 
 import_definition_slug | text                     |           |          | 
 import_name            | text                     |           |          | 
 import_note            | text                     |           |          | 
 target_schema_name     | text                     |           |          | 
 upload_table_name      | text                     |           |          | 
 data_table_name        | text                     |           |          | 
 source_column          | text                     |           |          | 
 source_value           | text                     |           |          | 
 source_expression      | import_source_expression |           |          | 
 target_column          | text                     |           |          | 
 target_type            | text                     |           |          | 
 uniquely_identifying   | boolean                  |           |          | 
 source_column_priority | integer                  |           |          | 

```
