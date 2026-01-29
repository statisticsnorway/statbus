```sql
                 View "public.enterprise_group__for_portion_of_valid"
          Column          |           Type           | Collation | Nullable | Default 
--------------------------+--------------------------+-----------+----------+---------
 id                       | integer                  |           |          | 
 valid_range              | daterange                |           |          | 
 valid_from               | date                     |           |          | 
 valid_to                 | date                     |           |          | 
 valid_until              | date                     |           |          | 
 short_name               | character varying(16)    |           |          | 
 name                     | character varying(256)   |           |          | 
 enterprise_group_type_id | integer                  |           |          | 
 contact_person           | text                     |           |          | 
 edit_comment             | character varying(512)   |           |          | 
 edit_by_user_id          | integer                  |           |          | 
 edit_at                  | timestamp with time zone |           |          | 
 unit_size_id             | integer                  |           |          | 
 data_source_id           | integer                  |           |          | 
 reorg_references         | text                     |           |          | 
 reorg_date               | timestamp with time zone |           |          | 
 reorg_type_id            | integer                  |           |          | 
 foreign_participation_id | integer                  |           |          | 
Triggers:
    for_portion_of_valid INSTEAD OF INSERT OR DELETE OR UPDATE ON enterprise_group__for_portion_of_valid FOR EACH ROW EXECUTE FUNCTION sql_saga.for_portion_of_trigger('id')

```
